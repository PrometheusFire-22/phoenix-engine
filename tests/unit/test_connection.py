"""Unit tests for database connection module."""

from chronos.database.connection import verify_database_connection
from unittest.mock import patch, MagicMock

# This file contains pure unit tests that use mocking to avoid real database connections.


@patch("chronos.database.connection.get_db_session")
def test_verify_db_connection_mocked_success(mock_get_db_session):
    """
    Unit test for verify_database_connection using a mocked session.
    This test simulates a successful connection.
    """
    # Configure the mock session
    mock_session = MagicMock()

    # --- THIS IS THE FIX ---
    # Configure the mock to handle multiple calls to 'execute'
    # The first call (version check) should return an object with a .scalar() method.
    # The second call (schema check) should return a list.
    version_check_result = MagicMock()
    version_check_result.scalar.return_value = "PostgreSQL 16.4"

    schema_check_result = [("metadata",), ("timeseries",)]

    mock_session.execute.side_effect = [version_check_result, schema_check_result]

    # Configure the context manager part of the mock
    mock_get_db_session.return_value.__enter__.return_value = mock_session

    # Run the function and assert it returns True
    assert verify_database_connection() is True
    assert mock_session.execute.call_count == 2  # Verify both queries ran


@patch("chronos.database.connection.get_db_session")
def test_verify_db_connection_mocked_failure(mock_get_db_session):
    """
    Unit test for verify_database_connection simulating a connection failure.
    """
    # Configure the mock to raise an exception, as a real failed connection would
    mock_get_db_session.return_value.__enter__.side_effect = Exception("Connection failed")

    # Run the function and assert it returns False
    assert verify_database_connection() is False
