"""
Project Chronos: Database Connection Management
================================================
Purpose: SQLAlchemy engine and session factory with connection pooling
Pattern: Context manager pattern for automatic session cleanup
"""

from contextlib import contextmanager
from typing import Generator

from sqlalchemy import create_engine, event, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import QueuePool

from chronos.config.settings import settings
from chronos.utils.logging import get_logger

logger = get_logger(__name__)


# ============================================================================
# SQLAlchemy Engine Configuration
# ============================================================================


def create_db_engine() -> Engine:
    """
    Create SQLAlchemy engine with production-grade configuration.

    Configuration details:
    - Connection pooling (QueuePool) for efficient connection reuse
    - Statement timeout to prevent runaway queries
    - Automatic UTC timezone enforcement
    - Echo mode for SQL logging in development

    Returns:
        Configured SQLAlchemy Engine instance
    """

    engine_kwargs = {
        "url": settings.database_url,
        "echo": settings.environment == "development",  # Log SQL in dev only
        "pool_pre_ping": True,  # Verify connections before use
        "pool_size": settings.database_pool_size,
        "max_overflow": settings.database_max_overflow,
        "pool_timeout": settings.database_pool_timeout,
        "poolclass": QueuePool,
        # Connection arguments
        "connect_args": {
            "options": "-c timezone=utc",  # Force UTC timestamps
            "connect_timeout": 10,
        },
    }

    engine = create_engine(**engine_kwargs)

    # Register event listeners
    _register_engine_events(engine)

    logger.info(
        "database_engine_created",
        host=settings.database_host,
        database=settings.database_name,
        pool_size=settings.database_pool_size,
    )

    return engine


def _register_engine_events(engine: Engine) -> None:
    """
    Register SQLAlchemy event listeners for operational best practices.

    Events:
    - Set statement timeout on new connections (prevent long-running queries)
    - Log connection pool statistics

    Args:
        engine: SQLAlchemy engine instance
    """

    @event.listens_for(engine, "connect")
    def receive_connect(dbapi_conn, connection_record):
        """Set statement timeout on new database connections."""
        with dbapi_conn.cursor() as cursor:
            # Kill queries running longer than 5 minutes (institutional standard)
            cursor.execute("SET statement_timeout = '300s'")
            logger.debug("connection_established", timeout="300s")


# ============================================================================
# Session Factory
# ============================================================================

# Global engine instance (created once per application lifecycle)
engine = create_db_engine()

# Session factory (thread-safe)
SessionLocal = sessionmaker(
    bind=engine,
    autocommit=False,
    autoflush=False,
    expire_on_commit=False,  # Prevent lazy-loading errors after commit
)


@contextmanager
def get_db_session() -> Generator[Session, None, None]:
    """
    Context manager for database sessions with automatic cleanup.

    Usage:
        >>> with get_db_session() as session:
        >>>     result = session.execute(text("SELECT 1"))
        >>>     session.commit()

    This pattern ensures:
    - Sessions are always closed (no connection leaks)
    - Transactions are rolled back on exceptions
    - Proper error propagation

    Yields:
        SQLAlchemy Session instance

    Raises:
        Exception: Re-raises any exception after rollback
    """
    session = SessionLocal()
    try:
        logger.debug("session_started")
        yield session
        session.commit()
        logger.debug("session_committed")
    except Exception as e:
        session.rollback()
        logger.error(
            "session_rollback",
            error=str(e),
            error_type=type(e).__name__,
        )
        raise
    finally:
        session.close()
        logger.debug("session_closed")


# ============================================================================
# Health Check Utilities
# ============================================================================


def verify_database_connection() -> bool:
    """
    Verify database connectivity and schema existence.

    Returns:
        True if connection successful and schemas exist, False otherwise
    """
    try:
        with get_db_session() as session:
            # Test basic connectivity
            result = session.execute(text("SELECT version()"))
            version = result.scalar()
            logger.info("database_connection_verified", postgres_version=version)

            # Verify schemas exist
            schema_check = session.execute(
                text(
                    """
                    SELECT schema_name
                    FROM information_schema.schemata
                    WHERE schema_name IN ('metadata', 'timeseries')
                """
                )
            )
            schemas = [row[0] for row in schema_check]

            if len(schemas) == 2:
                logger.info("database_schemas_verified", schemas=schemas)
                return True
            else:
                logger.error("database_schemas_missing", found=schemas)
                return False

    except Exception as e:
        logger.error(
            "database_connection_failed",
            error=str(e),
            error_type=type(e).__name__,
        )
        return False


def get_connection_pool_status() -> dict:
    """Get connection pool statistics (QueuePool only)."""
    pool = engine.pool

    # Check pool type
    if not isinstance(pool, QueuePool):
        return {"pool_type": type(pool).__name__, "status": "N/A"}

    return {
        "pool_type": "QueuePool",
        "pool_size": pool.size(),
        "checked_in": pool.checkedin(),
        "checked_out": pool.checkedout(),
        "overflow": pool.overflow(),
        "total_connections": pool.size() + pool.overflow(),
    }
