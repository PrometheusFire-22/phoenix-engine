"""
Project Chronos: Base Ingestion Class
======================================
Purpose: Abstract base class defining ingestion contract for all data sources
Pattern: Template Method pattern for consistent ingestion workflow
"""

from abc import ABC, abstractmethod
from datetime import datetime
from typing import List, Dict, Any, Optional
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.orm import Session

from chronos.utils.logging import get_logger

logger = get_logger(__name__)


class BaseIngestor(ABC):
    """
    Abstract base class for all data source ingestors.

    Transaction Management:
    - This class does NOT commit transactions internally
    - All database operations are managed by the external get_db_session() context manager
    - This ensures atomic transactions across multiple operations

    Subclasses must implement:
    - fetch_series_metadata()
    - fetch_observations()
    """

    def __init__(self, session: Session, source_name: str):
        """
        Initialize ingestor.

        Args:
            session: Active SQLAlchemy session (managed externally)
            source_name: Name from metadata.data_sources table
        """
        self.session = session
        self.source_name = source_name
        self.source_id = self._get_source_id()
        self.logger = get_logger(f"{__name__}.{source_name}")

    def _get_source_id(self) -> int:
        """
        Retrieve source_id from database.

        Returns:
            Source ID from metadata.data_sources

        Raises:
            ValueError: If source not found in database
        """
        result = self.session.execute(
            text("SELECT source_id FROM metadata.data_sources WHERE source_name = :name"),
            {"name": self.source_name},
        )
        row = result.fetchone()
        if not row:
            raise ValueError(f"Source '{self.source_name}' not found in data_sources table")
        return row[0]

    @abstractmethod
    def fetch_series_metadata(self, series_ids: List[str]) -> List[Dict[str, Any]]:
        """
        Fetch metadata for given series from external API.

        Args:
            series_ids: List of source-specific series identifiers

        Returns:
            List of metadata dictionaries with keys:
            - source_series_id (required)
            - series_name (required)
            - series_description
            - frequency
            - units
            - seasonal_adjustment
            - geography
        """
        pass

    @abstractmethod
    def fetch_observations(
        self,
        series_id: str,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> List[Dict[str, Any]]:
        """
        Fetch time-series observations from external API.

        Args:
            series_id: Source-specific series identifier
            start_date: Optional start date filter
            end_date: Optional end date filter

        Returns:
            List of observation dictionaries with keys:
            - date (required): date object
            - value (required): numeric value
        """
        pass

    def register_series(self, metadata: Dict[str, Any]) -> UUID:
        """
        Register series in database (idempotent).

        NOTE: Does NOT commit - transaction managed by caller.

        Args:
            metadata: Series metadata dictionary

        Returns:
            UUID of series (existing or newly created)
        """
        # Check if series already exists
        result = self.session.execute(
            text(
                """
                SELECT series_id FROM metadata.series_metadata
                WHERE source_id = :source_id AND source_series_id = :source_series_id
            """
            ),
            {"source_id": self.source_id, "source_series_id": metadata["source_series_id"]},
        )
        row = result.fetchone()

        if row:
            self.logger.debug(
                "series_already_registered", source_series_id=metadata["source_series_id"]
            )
            return row[0]

        # Insert new series
        result = self.session.execute(
            text(
                """
                INSERT INTO metadata.series_metadata (
                    source_id, source_series_id, series_name, series_description,
                    frequency, units, seasonal_adjustment, geography
                )
                VALUES (
                    :source_id, :source_series_id, :series_name, :series_description,
                    :frequency, :units, :seasonal_adjustment, :geography
                )
                RETURNING series_id
            """
            ),
            {
                "source_id": self.source_id,
                "source_series_id": metadata["source_series_id"],
                "series_name": metadata.get("series_name"),
                "series_description": metadata.get("series_description"),
                "frequency": metadata.get("frequency"),
                "units": metadata.get("units"),
                "seasonal_adjustment": metadata.get("seasonal_adjustment"),
                "geography": metadata.get("geography"),
            },
        )
        series_id = result.fetchone()[0]
        # NO COMMIT - Managed by external context manager

        self.logger.info(
            "series_registered",
            series_id=str(series_id),
            source_series_id=metadata["source_series_id"],
        )
        return series_id

    def store_observations(self, series_id: UUID, observations: List[Dict[str, Any]]) -> int:
        """
        Store observations in database (idempotent via ON CONFLICT).

        NOTE: Does NOT commit - transaction managed by caller.

        Args:
            series_id: UUID of series from series_metadata
            observations: List of {date, value} dictionaries

        Returns:
            Number of observations inserted/updated
        """
        if not observations:
            return 0

        # Bulk insert with conflict resolution (upsert)
        insert_query = text(
            """
            INSERT INTO timeseries.economic_observations (
                series_id, observation_date, value
            )
            VALUES (:series_id, :observation_date, :value)
            ON CONFLICT (series_id, observation_date)
            DO UPDATE SET
                value = EXCLUDED.value,
                updated_at = NOW()
        """
        )

        records = [
            {
                "series_id": series_id,
                "observation_date": obs["date"],
                "value": obs["value"],
            }
            for obs in observations
        ]

        self.session.execute(insert_query, records)
        # NO COMMIT - Managed by external context manager

        self.logger.info("observations_stored", series_id=str(series_id), count=len(records))
        return len(records)
