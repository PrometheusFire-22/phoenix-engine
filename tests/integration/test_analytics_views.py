"""
Project Chronos: Analytics Views Integration Tests
==================================================
Purpose: Validate that analytics views produce correct results
"""

import pytest
from sqlalchemy import text
from datetime import date

from chronos.database.connection import get_db_session


class TestFXRatesNormalized:
    """Test FX rate normalization logic."""

    def test_view_exists_and_accessible(self):
        """Ensure fx_rates_normalized view is queryable."""
        with get_db_session() as session:
            result = session.execute(
                text("SELECT COUNT(*) FROM analytics.fx_rates_normalized")
            )
            count = result.scalar()
            assert count > 0, "FX rates view should contain data"

    def test_usd_based_rates_not_transformed(self):
        """FRED rates like DEXUSEU should not be transformed (already USD-based)."""
        with get_db_session() as session:
            result = session.execute(
                text("""
                    SELECT 
                        source_series_id,
                        transformation_type,
                        raw_value,
                        usd_per_fx
                    FROM analytics.fx_rates_normalized
                    WHERE source_series_id = 'DEXUSEU'
                    LIMIT 1
                """)
            )
            row = result.fetchone()

            if row:
                assert row[1] == 'none', "DEXUSEU should have no transformation"
                assert row[2] == row[3], "Raw value should equal usd_per_fx for USD-based rates"

    def test_inverted_rates_transformed(self):
        """Rates like DEXCAUS (CAD/USD) should be inverted."""
        with get_db_session() as session:
            result = session.execute(
                text("""
                    SELECT 
                        source_series_id,
                        transformation_type,
                        raw_value,
                        usd_per_fx
                    FROM analytics.fx_rates_normalized
                    WHERE source_series_id = 'DEXCAUS'
                    LIMIT 1
                """)
            )
            row = result.fetchone()

            if row:
                assert row[1] == 'inverted', "DEXCAUS should be inverted"
                # USD per CAD = 1 / (CAD per USD)
                expected = 1.0 / float(row[2])
                assert abs(
                    float(row[3]) - expected) < 0.0001, "Inversion calculation incorrect"

    def test_cross_rate_calculation(self):
        """Bank of Canada cross-rates should be calculated correctly."""
        with get_db_session() as session:
            # Get FXEURCAD rate and corresponding USD/CAD rate
            result = session.execute(
                text("""
                    SELECT 
                        observation_date,
                        raw_value as eur_cad_rate,
                        usd_per_fx,
                        usd_cad_rate_used
                    FROM analytics.fx_rates_normalized
                    WHERE source_series_id = 'FXEURCAD'
                        AND usd_cad_rate_used IS NOT NULL
                    LIMIT 1
                """)
            )
            row = result.fetchone()

            if row:
                # USD per EUR = (CAD per EUR) × (USD per CAD)
                expected = row[1] * row[3]
                assert abs(
                    row[2] - expected) < 0.0001, "Cross-rate calculation incorrect"

    def test_no_null_normalized_values(self):
        """All normalized rates should have non-null usd_per_fx values."""
        with get_db_session() as session:
            result = session.execute(
                text("""
                    SELECT COUNT(*) 
                    FROM analytics.fx_rates_normalized
                    WHERE usd_per_fx IS NULL
                """)
            )
            null_count = result.scalar()
            assert null_count == 0, f"Found {null_count} NULL usd_per_fx values"


class TestMacroIndicatorsLatest:
    """Test macro indicators latest view."""

    def test_view_contains_data(self):
        """Ensure macro_indicators_latest returns rows."""
        with get_db_session() as session:
            result = session.execute(
                text("SELECT COUNT(*) FROM analytics.macro_indicators_latest")
            )
            count = result.scalar()
            assert count > 0, "Macro indicators view should contain data"

    def test_one_row_per_series(self):
        """Each series should appear exactly once (only latest)."""
        with get_db_session() as session:
            result = session.execute(
                text("""
                    SELECT source_series_id, COUNT(*) as count
                    FROM analytics.macro_indicators_latest
                    GROUP BY source_series_id
                    HAVING COUNT(*) > 1
                """)
            )
            duplicates = result.fetchall()
            assert len(
                duplicates) == 0, f"Found duplicate series: {duplicates}"

    def test_yoy_growth_calculation(self):
        """YoY growth should be calculated correctly."""
        with get_db_session() as session:
            result = session.execute(
                text("""
                    SELECT 
                        source_series_id,
                        latest_value,
                        value_1y_ago,
                        yoy_growth_pct
                    FROM analytics.macro_indicators_latest
                    WHERE value_1y_ago IS NOT NULL
                        AND yoy_growth_pct IS NOT NULL
                    LIMIT 1
                """)
            )
            row = result.fetchone()

            if row:
                expected_growth = 100.0 * \
                    (float(row[1]) - float(row[2])) / float(row[2])
                assert abs(
                    float(row[3]) - expected_growth) < 0.01, "YoY growth calculation incorrect"

    def test_latest_dates_are_recent(self):
        """Latest observations should be reasonably recent."""
        with get_db_session() as session:
            # Check which series have very old data
            result = session.execute(
                text("""
                    SELECT source_series_id, latest_date
                    FROM analytics.macro_indicators_latest
                    WHERE latest_date < '2020-01-01'
                """)
            )
            old_series = result.fetchall()

            # Allow up to 2 series to be discontinued/historical
            assert len(old_series) <= 2, \
                f"Too many series with very old data: {[(s[0], s[1]) for s in old_series]}"

            # Check that most series are recent
            result = session.execute(
                text("""
                    SELECT COUNT(*) 
                    FROM analytics.macro_indicators_latest
                    WHERE latest_date >= CURRENT_DATE - INTERVAL '6 months'
                """)
            )
            recent_count = result.scalar()

            # At least 80% of series should have recent data
            total = session.execute(
                text("SELECT COUNT(*) FROM analytics.macro_indicators_latest")
            ).scalar()

            assert recent_count >= (total * 0.8), \
                f"Only {recent_count}/{total} series have recent data"


class TestDataQualityDashboard:
    """Test data quality monitoring view."""

    def test_view_accessible(self):
        """Ensure data_quality_dashboard view is queryable."""
        with get_db_session() as session:
            result = session.execute(
                text("SELECT COUNT(*) FROM analytics.data_quality_dashboard")
            )
            count = result.scalar()
            assert count > 0, "Data quality dashboard should show series"

    def test_freshness_status_values(self):
        """Freshness status should only contain valid values."""
        valid_statuses = {'🟢 FRESH', '🟡 WARNING', '🔴 STALE', '⚪ NO DATA'}

        with get_db_session() as session:
            result = session.execute(
                text("""
                    SELECT DISTINCT freshness_status 
                    FROM analytics.data_quality_dashboard
                """)
            )
            statuses = {row[0] for row in result.fetchall()}

            assert statuses.issubset(valid_statuses), \
                f"Invalid statuses found: {statuses - valid_statuses}"

    def test_no_series_without_observations(self):
        """All active series should have at least some observations."""
        with get_db_session() as session:
            result = session.execute(
                text("""
                    SELECT source_series_id
                    FROM analytics.data_quality_dashboard
                    WHERE total_observations = 0
                """)
            )
            empty_series = result.fetchall()

            # Allow up to 2 series to be empty (might be newly added)
            assert len(empty_series) <= 2, \
                f"Too many series with no data: {[s[0] for s in empty_series]}"

    def test_null_percentage_calculation(self):
        """Null percentage should be between 0 and 100."""
        with get_db_session() as session:
            result = session.execute(
                text("""
                    SELECT source_series_id, null_pct
                    FROM analytics.data_quality_dashboard
                    WHERE null_pct < 0 OR null_pct > 100
                """)
            )
            invalid_pcts = result.fetchall()
            assert len(
                invalid_pcts) == 0, f"Invalid null percentages: {invalid_pcts}"


class TestViewPerformance:
    """Test that views perform acceptably."""

    @pytest.mark.slow
    def test_fx_rates_query_performance(self):
        """FX rates view should query quickly."""
        with get_db_session() as session:
            import time
            start = time.time()

            session.execute(
                text("""
                    SELECT * FROM analytics.fx_rates_normalized
                    WHERE observation_date >= CURRENT_DATE - INTERVAL '1 year'
                """)
            ).fetchall()

            elapsed = time.time() - start
            assert elapsed < 2.0, f"FX rates query too slow: {elapsed:.2f}s"

    @pytest.mark.slow
    def test_macro_indicators_query_performance(self):
        """Macro indicators view should query quickly."""
        with get_db_session() as session:
            import time
            start = time.time()

            session.execute(
                text("SELECT * FROM analytics.macro_indicators_latest")
            ).fetchall()

            elapsed = time.time() - start
            assert elapsed < 2.0, f"Macro indicators query too slow: {elapsed:.2f}s"


# Fixtures for test data validation
@pytest.fixture(scope="module")
def db_session():
    """Provide database session for tests."""
    with get_db_session() as session:
        yield session


@pytest.fixture(scope="module")
def series_count(db_session):
    """Get total number of series for reference."""
    result = db_session.execute(
        text("SELECT COUNT(*) FROM metadata.series_metadata")
    )
    return result.scalar()


def test_minimum_series_threshold(series_count):
    """Ensure we have minimum expected series."""
    assert series_count >= 38, f"Expected at least 38 series, found {series_count}"


def test_minimum_observations():
    """Ensure we have substantial data."""
    with get_db_session() as session:
        result = session.execute(
            text("SELECT COUNT(*) FROM timeseries.economic_observations")
        )
        obs_count = result.scalar()

        # With 38 series and historical data, expect 50k+ observations
        assert obs_count >= 50000, f"Expected 50k+ observations, found {obs_count}"
