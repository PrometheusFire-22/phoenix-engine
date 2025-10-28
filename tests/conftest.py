"""
Project Chronos: Pytest Configuration
======================================
Shared test fixtures and configuration
"""

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from chronos.config.settings import settings


@pytest.fixture(scope="session")
def test_engine():
    """Create test database engine."""
    engine = create_engine(settings.database_url)
    yield engine
    engine.dispose()


@pytest.fixture(scope="function")
def test_session(test_engine):
    """Create isolated test database session."""
    Session = sessionmaker(bind=test_engine)
    session = Session()
    
    yield session
    
    session.rollback()
    session.close()