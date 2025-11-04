"""
Project Chronos: Bank of Canada Valet Ingestion Tests
=====================================================
"""

import pytest
from datetime import datetime
from sqlalchemy import text

from chronos.database.connection import get_db_session
from chronos.ingestion.valet import ValetIngestor


class TestValetIngestor:
    """Test Bank of Canada Valet data ingestion."""

    @pytest.fixture
    def ingestor(self):
        """Provide ValetIngestor instance."""
        with get_db_session() as session:
            yield ValetIngestor(session)

    def test_ingestor_initialization(self, ingestor):
        """Ensure ValetIngestor initializes correctly."""
        assert ingestor is not None
        assert ingestor.source_id is not None

    def test_fetch_fx_series_metadata(self, ingestor):
        """Test fetching FX series metadata."""
        metadata = ingestor.fetch_series_metadata(["FXUSDCAD"])

        assert len(metadata) == 1
        assert metadata[0]["source_series_id"] == "FXUSDCAD"
        assert "USD" in metadata[0]["series_name"] or "CAD" in metadata[0]["series_name"]

    def test_fetch_observations_fxusdcad(self, ingestor):
        """Test fetching USD/CAD observations."""
        observations = ingestor.fetch_observations(
            "FXUSDCAD", start_date=datetime(2024, 1, 1), end_date=datetime(2024, 12, 31)
        )

        assert len(observations) > 0

        # Verify reasonable FX rate values (USD/CAD typically 1.2-1.4)
        for obs in observations:
            assert 0.5 < obs["value"] < 2.0, f"Unrealistic FX rate: {obs['value']}"

    def test_valet_data_quality(self):
        """Ensure Valet data meets quality standards."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT COUNT(*)
                    FROM metadata.series_metadata sm
                    JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
                    WHERE ds.source_name = 'VALET'
                        AND sm.is_active = TRUE
                """
                )
            )
            valet_series_count = result.scalar()

            assert valet_series_count >= 10, "Expected at least 10 Valet series"
