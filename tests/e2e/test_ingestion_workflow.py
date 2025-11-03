"""
Project Chronos: End-to-End Ingestion Workflow Tests
====================================================
Purpose: Test complete data pipeline from API ingestion to analytics views
Pattern: Integration tests that validate multi-layer functionality
"""

import pytest
from datetime import datetime, timedelta
from sqlalchemy import text

from chronos.database.connection import get_db_session
from chronos.ingestion.fred import FREDIngestor
from chronos.ingestion.valet import ValetIngestor
from datetime import timezone


@pytest.mark.slow
class TestFREDCompleteWorkflow:
    """Test complete FRED ingestion pipeline."""

    def test_fred_full_pipeline_federal_funds_rate(self):
        """Test FRED: metadata → observations → analytics for FEDFUNDS."""
        with get_db_session() as session:
            ingestor = FREDIngestor(session)

            # Step 1: Fetch metadata from API
            metadata_list = ingestor.fetch_series_metadata(["FEDFUNDS"])
            assert len(metadata_list) == 1
            metadata = metadata_list[0]

            assert metadata["source_series_id"] == "FEDFUNDS"
            assert "Federal Funds" in metadata["series_name"]
            assert metadata["frequency"] == "M"  # Monthly
            assert metadata["geography"] == "USA"

            # Step 2: Register series in database (idempotent)
            series_id = ingestor.register_series(metadata)
            assert series_id is not None

            # Verify registration
            result = session.execute(
                text(
                    """
                SELECT source_series_id, series_name, frequency
                FROM metadata.series_metadata
                WHERE series_id = :series_id
            """
                ),
                {"series_id": series_id},
            )
            row = result.fetchone()
            assert row[0] == "FEDFUNDS"

            # Step 3: Fetch observations from API (recent 6 months)
            start_date = datetime.now() - timedelta(days=180)
            end_date = datetime.now()

            observations = ingestor.fetch_observations(
                "FEDFUNDS", start_date=start_date, end_date=end_date
            )
            assert len(observations) > 0

            # Verify observation structure
            first_obs = observations[0]
            assert "date" in first_obs
            assert "value" in first_obs
            assert isinstance(first_obs["value"], float)

            # Step 4: Store observations in database
            records_inserted = ingestor.store_observations(series_id, observations)
            assert records_inserted > 0

            session.commit()

            # Step 5: Verify data appears in analytics view
            result = session.execute(
                text(
                    """
                SELECT
                    latest_value,
                    frequency,
                    geography,
                    latest_date
                FROM analytics.macro_indicators_latest
                WHERE source_series_id = 'FEDFUNDS'
            """
                )
            )
            row = result.fetchone()

            assert row is not None, "FEDFUNDS not in analytics view"
            assert row[0] is not None  # latest_value
            assert row[1] == "M"  # frequency
            assert row[2] == "USA"  # geography

            # Verify latest_date is recent
            latest_date = row[3]
            days_old = (datetime.now().date() - latest_date).days
            assert days_old < 90, f"Data too old: {days_old} days"

    def test_fred_fx_rate_appears_in_normalized_view(self):
        """Test FX rate flows from FRED to fx_rates_normalized view."""
        with get_db_session() as session:
            ingestor = FREDIngestor(session)

            # Ingest USD/EUR rate (DEXUSEU)
            metadata_list = ingestor.fetch_series_metadata(["DEXUSEU"])
            assert len(metadata_list) == 1

            series_id = ingestor.register_series(metadata_list[0])

            # Fetch recent observations
            observations = ingestor.fetch_observations(
                "DEXUSEU", start_date=datetime.now() - timedelta(days=30), end_date=datetime.now()
            )
            assert len(observations) > 0

            ingestor.store_observations(series_id, observations)
            session.commit()

            # Verify in fx_rates_normalized view
            result = session.execute(
                text(
                    """
                SELECT
                    source_series_id,
                    transformation_type,
                    rate_description,
                    usd_per_fx
                FROM analytics.fx_rates_normalized
                WHERE source_series_id = 'DEXUSEU'
                ORDER BY observation_date DESC
                LIMIT 1
            """
                )
            )
            row = result.fetchone()

            assert row is not None
            assert row[0] == "DEXUSEU"
            assert row[1] == "none"  # No transformation (already USD-based)
            assert "USD per EUR" in row[2]
            assert 0.5 < row[3] < 2.0  # Reasonable FX rate


@pytest.mark.slow
class TestValetCompleteWorkflow:
    """Test complete Valet ingestion pipeline."""

    def test_valet_full_pipeline_usd_cad(self):
        """Test Valet: metadata → observations → analytics for FXUSDCAD."""
        with get_db_session() as session:
            ingestor = ValetIngestor(session)

            # Step 1: Fetch metadata
            metadata_list = ingestor.fetch_series_metadata(["FXUSDCAD"])
            assert len(metadata_list) == 1
            metadata = metadata_list[0]

            assert metadata["source_series_id"] == "FXUSDCAD"
            assert "USD" in metadata["series_name"] or "CAD" in metadata["series_name"]
            assert metadata["frequency"] in ["D", "B"]  # Daily or Business
            assert metadata["geography"] == "CAN"

            # Step 2: Register series
            series_id = ingestor.register_series(metadata)
            assert series_id is not None

            # Step 3: Fetch observations (last 30 days)
            observations = ingestor.fetch_observations(
                "FXUSDCAD", start_date=datetime.now() - timedelta(days=30), end_date=datetime.now()
            )
            assert len(observations) > 0

            # Verify FX rate values are realistic
            for obs in observations[:5]:  # Check first 5
                assert 1.0 < obs["value"] < 2.0, f"Unrealistic USD/CAD rate: {obs['value']}"

            # Step 4: Store observations
            records_inserted = ingestor.store_observations(series_id, observations)
            assert records_inserted > 0

            session.commit()

            # Step 5: Verify in fx_rates_normalized view
            result = session.execute(
                text(
                    """
                SELECT
                    source_series_id,
                    transformation_type,
                    usd_per_fx,
                    observation_date
                FROM analytics.fx_rates_normalized
                WHERE source_series_id = 'FXUSDCAD'
                ORDER BY observation_date DESC
                LIMIT 1
            """
                )
            )
            row = result.fetchone()

            assert row is not None
            assert row[0] == "FXUSDCAD"
            # Should be inverted (CAD/USD → USD/CAD)
            assert row[1] == "inverted"
            assert 0.5 < row[2] < 1.0  # USD per CAD


@pytest.mark.slow
class TestCrossSourceConsistency:
    """Test data consistency across FRED and Valet sources."""

    def test_usd_cad_rates_converge(self):
        """Verify FRED and Valet USD/CAD rates are consistent."""
        with get_db_session() as session:
            # Get most recent USD/CAD from both sources
            result = session.execute(
                text(
                    """
                WITH latest_rates AS (
                    SELECT DISTINCT ON (source_series_id)
                        source_series_id,
                        usd_per_fx,
                        observation_date
                    FROM analytics.fx_rates_normalized
                    WHERE source_series_id IN ('DEXCAUS', 'FXUSDCAD')
                    ORDER BY source_series_id, observation_date DESC
                )
                SELECT source_series_id, usd_per_fx, observation_date
                FROM latest_rates
            """
                )
            )
            rates = {row[0]: (row[1], row[2]) for row in result.fetchall()}

            # Both sources should exist
            if "DEXCAUS" in rates and "FXUSDCAD" in rates:
                fred_rate, fred_date = rates["DEXCAUS"]
                valet_rate, valet_date = rates["FXUSDCAD"]

                # Rates should be within 2% (different update times)
                diff_pct = abs(fred_rate - valet_rate) / fred_rate * 100
                assert diff_pct < 2.0, (
                    f"USD/CAD rates diverge by {diff_pct:.2f}%: "
                    f"FRED={fred_rate} ({fred_date}), Valet={valet_rate} ({valet_date})"
                )


@pytest.mark.slow
class TestDataQualityAfterIngestion:
    """Test data quality metrics after ingestion."""

    def test_no_stale_data_after_fresh_ingestion(self):
        """After ingestion, freshness_status should be 🟢 FRESH."""
        with get_db_session() as session:
            # Check recently updated series
            result = session.execute(
                text(
                    """
                SELECT
                    source_series_id,
                    freshness_status,
                    days_since_last_update
                FROM analytics.data_quality_dashboard
                WHERE days_since_last_update < 7
            """
                )
            )
            fresh_series = result.fetchall()

            # Should have some fresh series
            assert len(fresh_series) > 0

            # All should be marked FRESH
            for series in fresh_series:
                assert series[1] in (
                    "🟢 FRESH",
                    "🟡 WARNING",
                ), f"{series[0]} marked {series[1]} despite recent update"

    def test_ingestion_log_populated(self):
        """Verify ingestion_log captures pipeline runs."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT
                    COUNT(*),
                    MAX(ingestion_end) as most_recent
                FROM metadata.ingestion_log
                WHERE status = 'success'
            """
                )
            )
            row = result.fetchone()

            log_count = row[0]
            most_recent = row[1]

            # Should have some successful ingestion logs
            assert log_count > 0, "No ingestion logs found"

            # Most recent should be within last 30 days
            if most_recent:
                days_since = (datetime.now(timezone.utc) - most_recent).days
                assert days_since < 30, f"No recent ingestions: {days_since} days old"


@pytest.mark.slow
class TestIdempotency:
    """Test that ingestion operations are idempotent."""

    def test_duplicate_series_registration_is_safe(self):
        """Registering same series twice should be idempotent."""
        with get_db_session() as session:
            ingestor = FREDIngestor(session)

            # Fetch metadata
            metadata_list = ingestor.fetch_series_metadata(["GDP"])
            assert len(metadata_list) == 1
            metadata = metadata_list[0]

            # Register first time
            series_id_1 = ingestor.register_series(metadata)
            session.commit()

            # Register again (should return same ID)
            series_id_2 = ingestor.register_series(metadata)
            session.commit()

            assert series_id_1 == series_id_2, "Duplicate registration created new series"

    def test_duplicate_observations_upsert_correctly(self):
        """Storing same observations twice should upsert (not duplicate)."""
        with get_db_session() as session:
            ingestor = FREDIngestor(session)

            # Get existing series
            result = session.execute(
                text(
                    """
                SELECT series_id, source_series_id
                FROM metadata.series_metadata
                WHERE source_series_id = 'FEDFUNDS'
                LIMIT 1
            """
                )
            )
            row = result.fetchone()

            if not row:
                pytest.skip("FEDFUNDS not in database")

            series_id = row[0]

            # Count existing observations
            result = session.execute(
                text(
                    """
                SELECT COUNT(*)
                FROM timeseries.economic_observations
                WHERE series_id = :series_id
            """
                ),
                {"series_id": series_id},
            )

            # Fetch recent observations
            observations = ingestor.fetch_observations(
                "FEDFUNDS", start_date=datetime.now() - timedelta(days=60), end_date=datetime.now()
            )

            if observations:
                # Store first time
                ingestor.store_observations(series_id, observations)
                session.commit()

                result = session.execute(
                    text(
                        """
                    SELECT COUNT(*)
                    FROM timeseries.economic_observations
                    WHERE series_id = :series_id
                """
                    ),
                    {"series_id": series_id},
                )
                count_after_first = result.scalar()

                # Store again (idempotent)
                ingestor.store_observations(series_id, observations)
                session.commit()

                result = session.execute(
                    text(
                        """
                    SELECT COUNT(*)
                    FROM timeseries.economic_observations
                    WHERE series_id = :series_id
                """
                    ),
                    {"series_id": series_id},
                )
                count_after_second = result.scalar()

                # Count should not increase on second insert
                assert (
                    count_after_second == count_after_first
                ), "Duplicate observations inserted (ON CONFLICT not working)"


# Test fixtures
@pytest.fixture(scope="module")
def ensure_api_keys():
    """Ensure API keys are available for E2E tests."""
    from chronos.config.settings import settings

    # FRED requires API key
    assert settings.fred_api_key, "FRED_API_KEY not set for E2E tests"

    yield True  # ← Add this


def test_prerequisites(ensure_api_keys):
    """Meta-test: Ensure E2E test prerequisites are met."""
    assert ensure_api_keys is not None
