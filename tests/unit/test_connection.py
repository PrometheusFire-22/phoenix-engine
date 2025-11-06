"""Unit tests for database connection module."""

import pytest
from chronos.database.connection import verify_database_connection


# This test requires a live database. It is an INTEGRATION test.
# We mark it as such to exclude it from the fast pre-commit hooks.
@pytest.mark.integration
def test_database_connection():
    """
    [Integration Test]
    Tests real database connectivity.
    This test is automatically skipped by the pre-commit hook.
    """
    assert verify_database_connection() is True
