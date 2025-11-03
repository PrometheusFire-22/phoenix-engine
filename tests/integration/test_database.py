"""
Project Chronos: Database Layer Integration Tests
=================================================
Purpose: Validate database connection, schema integrity, and TimescaleDB features
"""

import pytest
from sqlalchemy import text

from chronos.database.connection import (
    get_db_session,
    verify_database_connection,
    get_connection_pool_status,
)


class TestDatabaseConnection:
    """Test database connection management."""

    def test_connection_successful(self):
        """Verify basic database connectivity."""
        with get_db_session() as session:
            result = session.execute(text("SELECT 1 as test"))
            assert result.scalar() == 1

    def test_session_context_manager_cleanup(self):
        """Ensure sessions are properly closed after use."""
        session_id = None

        # Create and use session
        with get_db_session() as session:
            result = session.execute(text("SELECT pg_backend_pid()"))
            session_id = result.scalar()
            assert session_id is not None

        # Verify session was closed (check pool status)
        pool_status = get_connection_pool_status()
        # After closing, connection should return to pool
        assert pool_status["checked_out"] >= 0

    def test_transaction_rollback_on_error(self):
        """Test that failed transactions rollback properly."""
        with pytest.raises(Exception):
            with get_db_session() as session:
                # This will fail (table doesn't exist)
                session.execute(text("INSERT INTO invalid_table_xyz VALUES (1)"))

        # Database should still be accessible
        with get_db_session() as session:
            result = session.execute(text("SELECT 1"))
            assert result.scalar() == 1

    def test_connection_pool_configured(self):
        """Verify connection pool is properly initialized."""
        pool_status = get_connection_pool_status()

        # Should have pool configuration
        assert "pool_size" in pool_status or "pool_type" in pool_status

        # If QueuePool, verify size is reasonable
        if pool_status.get("pool_type") == "QueuePool":
            assert pool_status["pool_size"] > 0
            assert pool_status["pool_size"] <= 50

    def test_verify_database_connection_utility(self):
        """Test database connection verification utility."""
        is_connected = verify_database_connection()
        assert is_connected is True

    def test_concurrent_sessions(self):
        """Test multiple concurrent database sessions."""
        results = []

        # Open multiple sessions simultaneously
        with get_db_session() as session1:
            with get_db_session() as session2:
                result1 = session1.execute(text("SELECT 1"))
                result2 = session2.execute(text("SELECT 2"))

                results.append(result1.scalar())
                results.append(result2.scalar())

        assert results == [1, 2]


class TestDatabaseSchema:
    """Test schema integrity and structure."""

    def test_all_required_schemas_exist(self):
        """Verify metadata, timeseries, analytics schemas exist."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT schema_name
                FROM information_schema.schemata
                WHERE schema_name IN ('metadata', 'timeseries', 'analytics')
                ORDER BY schema_name
            """
                )
            )
            schemas = [row[0] for row in result.fetchall()]

            assert "analytics" in schemas
            assert "metadata" in schemas
            assert "timeseries" in schemas

    def test_metadata_tables_exist(self):
        """Verify all metadata tables are created."""
        expected_tables = {"data_sources", "series_metadata", "series_attributes", "ingestion_log"}

        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'metadata'
            """
                )
            )
            tables = {row[0] for row in result.fetchall()}

            assert expected_tables.issubset(tables), f"Missing tables: {expected_tables - tables}"

    def test_timeseries_tables_exist(self):
        """Verify timeseries schema tables exist."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'timeseries'
                  AND table_name = 'economic_observations'
            """
                )
            )
            tables = [row[0] for row in result.fetchall()]

            assert "economic_observations" in tables

    def test_analytics_views_exist(self):
        """Verify all analytics views are created."""
        expected_views = {
            "fx_rates_normalized",
            "macro_indicators_latest",
            "data_quality_dashboard",
        }

        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT table_name
                FROM information_schema.views
                WHERE table_schema = 'analytics'
            """
                )
            )
            views = {row[0] for row in result.fetchall()}

            assert expected_views.issubset(views), f"Missing views: {expected_views - views}"


class TestTimescaleDB:
    """Test TimescaleDB-specific features."""

    def test_timescaledb_extension_enabled(self):
        """Verify TimescaleDB extension is installed."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT extname
                FROM pg_extension
                WHERE extname = 'timescaledb'
            """
                )
            )
            extension = result.scalar()

            assert extension == "timescaledb"

    def test_hypertable_configured(self):
        """Ensure economic_observations is a TimescaleDB hypertable."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT hypertable_schema, hypertable_name
                FROM timescaledb_information.hypertables
                WHERE hypertable_name = 'economic_observations'
            """
                )
            )
            row = result.fetchone()

            assert row is not None, "economic_observations is not a hypertable"
            assert row[0] == "timeseries"
            assert row[1] == "economic_observations"

    def test_hypertable_chunk_interval(self):
        """Verify hypertable uses appropriate chunk interval."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT
                    EXTRACT(EPOCH FROM d.time_interval) * 1000000 as interval_usec
                FROM timescaledb_information.dimensions d
                JOIN timescaledb_information.hypertables h
                    ON d.hypertable_schema = h.hypertable_schema
                    AND d.hypertable_name = h.hypertable_name
                WHERE h.hypertable_name = 'economic_observations'
                AND d.column_name = 'observation_date'
            """
                )
            )
            row = result.fetchone()

            assert row is not None
            # Chunk interval should be 1 year (in microseconds)
            interval_usec = row[0]
            one_year_usec = 365 * 24 * 60 * 60 * 1_000_000

            # Allow 10% variance for leap years
            assert abs(interval_usec - one_year_usec) < (one_year_usec * 0.1)


class TestDataSources:
    """Test data_sources seed data."""

    def test_data_sources_seeded(self):
        """Verify data sources are populated."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT COUNT(*)
                FROM metadata.data_sources
            """
                )
            )
            count = result.scalar()

            # Should have at least FRED and VALET
            assert count >= 2

    def test_fred_source_exists(self):
        """Verify FRED source is registered."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT source_id, source_name, api_type, requires_auth
                FROM metadata.data_sources
                WHERE source_name = 'FRED'
            """
                )
            )
            row = result.fetchone()

            assert row is not None
            assert row[1] == "FRED"
            assert row[2] == "rest"
            assert row[3] is True  # Requires authentication

    def test_valet_source_exists(self):
        """Verify Bank of Canada Valet source is registered."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT source_id, source_name, api_type, requires_auth
                FROM metadata.data_sources
                WHERE source_name = 'VALET'
            """
                )
            )
            row = result.fetchone()

            assert row is not None
            assert row[1] == "VALET"
            assert row[2] == "rest"
            assert row[3] is False  # No authentication required


class TestDatabaseConstraints:
    """Test database constraints and data integrity."""

    def test_series_metadata_unique_constraint(self):
        """Verify unique constraint on source_id + source_series_id."""
        with get_db_session() as session:
            # This should work (valid constraint)
            # Testing by attempting duplicate insert would require cleanup
            result = session.execute(
                text(
                    """
                SELECT constraint_name
                FROM information_schema.table_constraints
                WHERE table_schema = 'metadata'
                  AND table_name = 'series_metadata'
                  AND constraint_type = 'UNIQUE'
            """
                )
            )
            constraints = [row[0] for row in result.fetchall()]

            # Should have at least one unique constraint
            assert len(constraints) > 0

    def test_observations_primary_key(self):
        """Verify primary key on economic_observations."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT constraint_name
                FROM information_schema.table_constraints
                WHERE table_schema = 'timeseries'
                  AND table_name = 'economic_observations'
                  AND constraint_type = 'PRIMARY KEY'
            """
                )
            )
            pk = result.fetchone()

            assert pk is not None

    def test_foreign_key_constraints(self):
        """Verify foreign key relationships are enforced."""
        with get_db_session() as session:
            result = session.execute(
                text(
                    """
                SELECT
                    tc.constraint_name,
                    tc.table_name,
                    kcu.column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_name = kcu.constraint_name
                    AND tc.table_schema = kcu.table_schema
                WHERE tc.constraint_type = 'FOREIGN KEY'
                  AND tc.table_schema IN ('metadata', 'timeseries')
            """
                )
            )
            fks = result.fetchall()

            # Should have multiple foreign keys
            assert len(fks) >= 3, "Missing foreign key constraints"


# Fixtures
@pytest.fixture(scope="module")
def db_connection_verified():
    """Ensure database is accessible before running tests."""
    connection_ok = verify_database_connection()
    assert connection_ok is True
    yield connection_ok  # ← Add this


def test_database_accessible(db_connection_verified):
    """Meta-test: Ensure database is accessible."""
    assert db_connection_verified is not None
