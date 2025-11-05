"""Unit tests for database connection module."""
import pytest
import os
from chronos.database.connection import verify_database_connection


@pytest.mark.skipif(
    os.getenv("CI") == "true" or os.getenv("GITHUB_ACTIONS") == "true",
    reason="Database test skipped in CI (covered by integration tests)"
)
def test_database_connection():
    """Test database connectivity (skipped in CI)."""
    assert verify_database_connection() is True
