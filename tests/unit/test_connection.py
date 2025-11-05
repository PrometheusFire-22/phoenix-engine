"""
Unit tests for database connection module.

NOTE: This test is skipped in CI environments where database is not available
during unit test phase. Integration tests cover actual database connectivity.
"""

import pytest
import os
from chronos.database.connection import verify_database_connection


@pytest.mark.skipif(
    os.getenv("CI") == "true",
    reason="Database connection test skipped in CI (covered by integration tests)"
)
def test_database_connection():
    """Test database connectivity (skipped in CI environments)."""
    assert verify_database_connection() is True
