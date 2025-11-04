"""
Project Chronos: Database Connection Tests
"""

from chronos.database.connection import verify_database_connection


def test_database_connection():
    """Test basic database connectivity."""
    assert verify_database_connection() is True
