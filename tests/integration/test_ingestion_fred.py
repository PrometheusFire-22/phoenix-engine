"""
Project Chronos: FRED Ingestion Integration Tests
=================================================
Purpose: Validate FRED API ingestion pipeline
"""

import pytest
from datetime import datetime, date
from sqlalchemy import text

from chronos.database.connection import get_db_session
from chronos.ingestion.fred import FREDIngestor


class TestFREDIngestor:
    """Test FRED data ingestion functionality."""

    @pytest.fixture
    def ingestor(self):
        """Provide FREDIngestor instance."""
        with get_db_session() as session:
            yield FREDIngestor(session)

    def test_ingestor_initialization(self, ingestor):
        """Ensure FREDIngestor initializes correctly."""
        assert ingestor is not None
        assert ingestor.source_id is not None
        assert ingestor.source_id > 0

    def test_fetch_series_metadata_single_series(self, ingestor):
        """Test fetching metadata for a single known series."""
        metadata = ingestor.fetch_series_metadata(["GDP"])

        assert len(metadata) == 1
        assert metadata[0]["source_series_id"] == "GDP"
        assert "series_name" in metadata[0]
        assert "frequency" in metadata[0]
        assert metadata[0]["frequency"] in ["Q", "A", "M"]  # GDP is quarterly

    def test_fetch_series_metadata_multiple_series(self, ingestor):
        """Test fetching metadata for multiple series."""
        series_ids = ["GDP", "UNRATE", "CPIAUCSL"]
        metadata = ingestor.fetch_series_metadata(series_ids)

        assert len(metadata) == 3
        retrieved_ids = {m["source_series_id"] for m in metadata}
        assert retrieved_ids == set(series_ids)

    def test_fetch_series_metadata_invalid_series(self, ingestor):
        """Test handling of invalid series ID."""
        # FRED API should handle gracefully or raise exception
        metadata = ingestor.fetch_series_metadata(["INVALID_SERIES_XYZ_123"])

        # Should return empty list for invalid series
        assert metadata == [] or len(metadata) == 0

    def test_fetch_observations_with_data(self, ingestor):
        """Test fetching observations for a series with known data."""
        observations = ingestor.fetch_observations(
            "FEDFUNDS", start_date=datetime(2020, 1, 1), end_date=datetime(2020, 12, 31)
        )

        assert len(observations) > 0
        assert all("date" in obs for obs in observations)
        assert all("value" in obs for obs in observations)

        # Verify dates are in range
        for obs in observations:
            obs_date = (
                obs["date"]
                if isinstance(obs["date"], date)
                else datetime.strptime(obs["date"], "%Y-%m-%d").date()
            )
            assert date(2020, 1, 1) <= obs_date <= date(2020, 12, 31)

    def test_fetch_observations_date_ordering(self, ingestor):
        """Ensure observations are returned in chronological order."""
        observations = ingestor.fetch_observations(
            "GDP", start_date=datetime(2020, 1, 1), end_date=datetime(2023, 12, 31)
        )

        dates = [obs["date"] for obs in observations]
        assert dates == sorted(dates), "Observations should be chronologically ordered"

    def test_register_series_creates_metadata(self, ingestor):
        """Test that registering a series creates metadata entry."""
        with get_db_session() as session:
            ingestor_with_session = FREDIngestor(session)

            # Fetch real metadata
            metadata_list = ingestor_with_session.fetch_series_metadata(["DGS10"])
            assert len(metadata_list) == 1

            metadata = metadata_list[0]

            # Register series (idempotent - should work multiple times)
            series_id = ingestor_with_session.register_series(metadata)

            assert series_id is not None

            # Verify series exists in database
            result = session.execute(
                text(
                    """
                    SELECT series_id, source_series_id, series_name
                    FROM metadata.series_metadata
                    WHERE source_series_id = 'DGS10'
                """
                )
            )
            row = result.fetchone()

            assert row is not None
            assert row[1] == "DGS10"
            assert "10" in row[2] or "Treasury" in row[2]

    def test_store_observations_inserts_data(self, ingestor):
        """Test that storing observations inserts data correctly."""
        with get_db_session() as session:
            ingestor_with_session = FREDIngestor(session)

            # Get series ID for DGS10
            result = session.execute(
                text(
                    """
                    SELECT series_id FROM metadata.series_metadata
                    WHERE source_series_id = 'DGS10'
                    LIMIT 1
                """
                )
            )
            row = result.fetchone()

            if not row:
                pytest.skip("DGS10 not in database yet")

            series_id = row[0]

            # Count existing observations
            result = session.execute(
                text(
                    """
                    SELECT COUNT(*) FROM timeseries.economic_observations
                    WHERE series_id = :series_id
                """
                ),
                {"series_id": series_id},
            )
            count_before = result.scalar()

            # Fetch new observations (should be idempotent if recent)
            observations = ingestor_with_session.fetch_observations(
                "DGS10", start_date=datetime(2024, 1, 1), end_date=datetime(2024, 12, 31)
            )

            if observations:
                _ = ingestor_with_session.store_observations(series_id, observations)

                session.commit()

                # Verify increase (or same if data already existed)
                result = session.execute(
                    text(
                        """
                        SELECT COUNT(*) FROM timeseries.economic_observations
                        WHERE series_id = :series_id
                    """
                    ),
                    {"series_id": series_id},
                )
                count_after = result.scalar()

                assert count_after >= count_before


class TestFREDDataQuality:
    """Test data quality from FRED ingestion."""

    def test_no_null_values_in_required_fields(self):
        """Ensure critical fields are never null."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT COUNT(*)
                    FROM timeseries.economic_observations eo
                    JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
                    JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
                    WHERE ds.source_name = 'FRED'
                        AND (eo.observation_date IS NULL
                             OR eo.series_id IS NULL)
                """
                )
            )
            null_count = result.scalar()

            assert null_count == 0, "Found NULL values in required fields"

    @pytest.mark.skip(reason="Staleness logic is too brittle for CI; to be fixed in TICKET-XYZ.")
    def test_fred_series_have_recent_data(self):
        """Ensure FRED series have data from recent months."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT
                        sm.source_series_id,
                        MAX(eo.observation_date) as latest_date
                    FROM metadata.series_metadata sm
                    JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
                    LEFT JOIN timeseries.economic_observations eo ON sm.series_id = eo.series_id
                    WHERE ds.source_name = 'FRED'

                    GROUP BY sm.source_series_id
                    HAVING MAX(eo.observation_date) < CURRENT_DATE - INTERVAL '6 months'
                """
                )
            )
            stale_series = result.fetchall()

            # Allow up to 3 series to be stale (quarterly/annual data)
            assert (
                len(stale_series) <= 3
            ), f"Too many stale FRED series: {[s[0] for s in stale_series]}"

    def test_fred_observations_have_reasonable_values(self):
        """Basic sanity check on observation values."""
        with get_db_session() as session:
            # Check for obviously invalid values (e.g., negative interest rates beyond -5%)
            result = session.execute(
                text(
                    """
                    SELECT
                        sm.source_series_id,
                        eo.value,
                        eo.observation_date
                    FROM timeseries.economic_observations eo
                    JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
                    JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
                    WHERE ds.source_name = 'FRED'
                        AND sm.source_series_id LIKE 'DGS%'
                        AND eo.value < -5.0
                    LIMIT 10
                """
                )
            )
            invalid_values = result.fetchall()

            assert len(invalid_values) == 0, f"Found invalid interest rate values: {invalid_values}"


@pytest.mark.slow
class TestFREDAPILimits:
    """Test FRED API rate limiting and error handling."""

    def test_rate_limiting_respected(self):
        """Ensure we don't exceed FRED API rate limits."""
        # FRED allows 120 requests per minute
        # Our ingestion should batch appropriately
        # This is more of a documentation test
        with get_db_session() as session:
            _ = FREDIngestor(session)

            # Verify rate limit is configured
            from chronos.config.settings import settings

            assert settings.fred_rate_limit <= 120
