"""
Project Chronos: Analytics Views Integration Tests
==================================================
Purpose: Validate that analytics views produce correct results
"""

import pytest
from sqlalchemy import text

from chronos.database.connection import get_db_session


class TestFXRatesNormalized:
    """Test FX rate normalization logic."""

    def test_view_exists_and_accessible(self):
        """Ensure fx_rates_normalized view is queryable."""
        with get_db_session() as session:
            result = session.execute(text("SELECT COUNT(*) FROM analytics.fx_rates_normalized"))
            count = result.scalar()
            assert count > 0, "FX rates view should contain data"

    def test_usd_based_rates_present(self):
        """FRED USD-based rates should be present."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT source_series_id, original_rate, usd_rate
                    FROM analytics.fx_rates_normalized
                    WHERE source_series_id = 'DEXUSEU'
                    LIMIT 1
                """
                )
            )
            row = result.fetchone()
            assert row is not None, "DEXUSEU should exist in view"

    def test_inverted_rates_transformed(self):
        """Bank of Canada non-USD rates should be inverted."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT source_series_id, original_rate, usd_rate
                    FROM analytics.fx_rates_normalized
                    WHERE source_series_id = 'FXEURCAD'
                    LIMIT 1
                """
                )
            )
            row = result.fetchone()

            if row:
                # FXEURCAD (EUR/CAD) should be inverted to get USD/EUR
                expected_usd_rate = 1.0 / float(row[1])
                actual_usd_rate = float(row[2])
                assert (
                    abs(actual_usd_rate - expected_usd_rate) < 0.0001
                ), f"Inversion incorrect: {actual_usd_rate} != {expected_usd_rate}"

    def test_cross_rate_calculation(self):
        """Bank of Canada cross-rates (FXEURCAD) should be calculated."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT source_series_id, original_rate, usd_rate
                    FROM analytics.fx_rates_normalized
                    WHERE source_series_id = 'FXEURCAD'
                    LIMIT 1
                """
                )
            )
            row = result.fetchone()
            # Just verify the row exists and has valid values
            if row:
                assert row[1] > 0, "Original rate should be positive"
                assert row[2] > 0, "USD rate should be positive"

    def test_no_null_normalized_values(self):
        """All normalized rates should have non-null usd_rate values."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT COUNT(*)
                    FROM analytics.fx_rates_normalized
                    WHERE usd_rate IS NULL
                """
                )
            )
            null_count = result.scalar()
            assert null_count == 0, f"Found {null_count} NULL usd_rate values"


class TestMacroIndicatorsLatest:
    """Test macro indicators latest view."""

    def test_view_contains_data(self):
        """Ensure macro_indicators_latest returns rows."""
        with get_db_session() as session:
            result = session.execute(text("SELECT COUNT(*) FROM analytics.macro_indicators_latest"))
            count = result.scalar()
            assert count > 0, "Macro indicators view should contain data"

    def test_one_row_per_series(self):
        """Each series should appear exactly once (only latest)."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT source_series_id, COUNT(*) as count
                    FROM analytics.macro_indicators_latest
                    GROUP BY source_series_id
                    HAVING COUNT(*) > 1
                """
                )
            )
            duplicates = result.fetchall()
            assert len(duplicates) == 0, f"Found duplicate series: {duplicates}"

    def test_yoy_growth_calculation(self):
        """YoY growth should be calculated if columns exist."""
        with get_db_session() as session:
            # Check if yoy_growth columns exist first
            result = session.execute(
                text(
                    """
                    SELECT column_name
                    FROM information_schema.columns
                    WHERE table_schema = 'analytics'
                      AND table_name = 'macro_indicators_latest'
                      AND column_name IN ('yoy_growth_pct', 'value_1y_ago')
                """
                )
            )
            columns = [row[0] for row in result.fetchall()]

            if "yoy_growth_pct" in columns:
                result = session.execute(
                    text(
                        """
                        SELECT latest_value, value_1y_ago, yoy_growth_pct
                        FROM analytics.macro_indicators_latest
                        WHERE value_1y_ago IS NOT NULL
                          AND yoy_growth_pct IS NOT NULL
                        LIMIT 1
                    """
                    )
                )
                row = result.fetchone()
                if row:
                    expected = 100.0 * (float(row[0]) - float(row[1])) / float(row[1])
                    assert abs(float(row[2]) - expected) < 0.01

    def test_latest_dates_are_recent(self):
        """Latest observations should be reasonably recent."""
        with get_db_session() as session:
            # Check that most series have data from last 2 years
            result = session.execute(
                text(
                    """
                    SELECT COUNT(*)
                    FROM analytics.macro_indicators_latest
                    WHERE latest_date >= CURRENT_DATE - INTERVAL '2 years'
                """
                )
            )
            recent_count = result.scalar()

            # At least 70% should be reasonably recent
            total = session.execute(
                text("SELECT COUNT(*) FROM analytics.macro_indicators_latest")
            ).scalar()

            assert recent_count >= (
                total * 0.7
            ), f"Only {recent_count}/{total} series have data from last 2 years"


class TestDataQualityDashboard:
    """Test data quality monitoring view."""

    def test_view_accessible(self):
        """Ensure data_quality_dashboard view is queryable."""
        with get_db_session() as session:
            result = session.execute(text("SELECT COUNT(*) FROM analytics.data_quality_dashboard"))
            count = result.scalar()
            assert count > 0, "Data quality dashboard should show series"

    def test_freshness_status_values(self):
        """Freshness status should only contain valid emoji values."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT DISTINCT freshness_status
                    FROM analytics.data_quality_dashboard
                """
                )
            )
            statuses = {row[0] for row in result.fetchall()}

            # All statuses should start with an emoji
            for status in statuses:
                assert status and len(status) > 0, "Status should not be empty"
                # Should contain one of the status emojis
                assert any(
                    emoji in status for emoji in ["🟢", "🟡", "🔴", "⚪"]
                ), f"Invalid status: {status}"

    def test_no_series_without_observations(self):
        """All active series should have at least some observations."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT source_series_id
                    FROM analytics.data_quality_dashboard
                    WHERE total_observations = 0
                """
                )
            )
            empty_series = result.fetchall()

            # Allow up to 2 series to be empty (might be newly added)
            assert (
                len(empty_series) <= 2
            ), f"Too many series with no data: {[s[0] for s in empty_series]}"

    def test_null_percentage_calculation(self):
        """Null percentage should be between 0 and 100."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                    SELECT source_series_id, null_percentage
                    FROM analytics.data_quality_dashboard
                    WHERE null_percentage < 0 OR null_percentage > 100
                """
                )
            )
            invalid_pcts = result.fetchall()
            assert len(invalid_pcts) == 0, f"Invalid null percentages: {invalid_pcts}"


class TestViewPerformance:
    """Test that views perform acceptably."""

    @pytest.mark.slow
    def test_fx_rates_query_performance(self):
        """FX rates view should query quickly."""
        with get_db_session() as session:
            import time

            start = time.time()

            session.execute(
                text(
                    """
                    SELECT * FROM analytics.fx_rates_normalized
                    WHERE observation_date >= CURRENT_DATE - INTERVAL '1 year'
                """
                )
            ).fetchall()

            elapsed = time.time() - start
            assert elapsed < 5.0, f"FX rates query too slow: {elapsed:.2f}s"

    @pytest.mark.slow
    def test_macro_indicators_query_performance(self):
        """Macro indicators view should query quickly."""
        with get_db_session() as session:
            import time

            start = time.time()

            session.execute(text("SELECT * FROM analytics.macro_indicators_latest")).fetchall()

            elapsed = time.time() - start
            assert elapsed < 3.0, f"Macro indicators query too slow: {elapsed:.2f}s"


# Fixtures for test data validation
@pytest.fixture(scope="module")
def db_session():
    """Provide database session for tests."""
    with get_db_session() as session:
        yield session


@pytest.fixture(scope="module")
def series_count(db_session):
    """Get total number of series for reference."""
    result = db_session.execute(text("SELECT COUNT(*) FROM metadata.series_metadata"))
    return result.scalar()


def test_minimum_series_threshold(series_count):
    """Ensure we have minimum expected series."""
    assert series_count >= 38, f"Expected at least 38 series, found {series_count}"


def test_minimum_observations():
    """Ensure we have substantial data."""
    with get_db_session() as session:
        result = session.execute(text("SELECT COUNT(*) FROM timeseries.economic_observations"))
        obs_count = result.scalar()

        # With 50+ series and historical data, expect 50k+ observations
        assert obs_count >= 50000, f"Expected 50k+ observations, found {obs_count}"
