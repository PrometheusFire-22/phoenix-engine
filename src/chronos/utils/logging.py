"""
Project Chronos: Structured Logging Configuration
==================================================
Purpose: Production-grade logging with JSON output for log aggregation
Pattern: Structlog for machine-readable logs (critical for monitoring)
"""

import logging
import sys
from typing import Any

import structlog
from structlog.types import EventDict, WrappedLogger

from chronos.config.settings import settings


def add_app_context(
    logger: WrappedLogger, method_name: str, event_dict: EventDict
) -> EventDict:
    """
    Add application-wide context to every log entry.
    
    Args:
        logger: Structlog logger instance
        method_name: Logging method name
        event_dict: Log event dictionary
        
    Returns:
        Enhanced event dictionary with app context
    """
    event_dict["app"] = "chronos"
    event_dict["environment"] = settings.environment
    return event_dict


def configure_logging() -> None:
    """
    Configure application-wide structured logging.
    
    This setup:
    - Uses JSON formatting for production (machine-readable)
    - Uses console formatting for development (human-readable)
    - Adds timestamps, log levels, and contextual information
    - Integrates with Python's standard logging module
    """
    
    # Determine output format based on configuration
    if settings.log_format == "json":
        processors = [
            structlog.stdlib.add_log_level,
            structlog.stdlib.add_logger_name,
            structlog.processors.TimeStamper(fmt="iso"),
            add_app_context,
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ]
    else:
        processors = [
            structlog.stdlib.add_log_level,
            structlog.stdlib.add_logger_name,
            structlog.processors.TimeStamper(fmt="%Y-%m-%d %H:%M:%S"),
            add_app_context,
            structlog.dev.ConsoleRenderer(),
        ]
    
    # Configure structlog
    structlog.configure(
        processors=processors,
        wrapper_class=structlog.stdlib.BoundLogger,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )
    
    # Configure standard library logging (used by SQLAlchemy, etc.)
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, settings.log_level),
    )


def get_logger(name: str) -> structlog.stdlib.BoundLogger:
    """
    Get a configured logger instance.
    
    Args:
        name: Logger name (typically __name__ from calling module)
        
    Returns:
        Configured structlog logger
        
    Example:
        >>> logger = get_logger(__name__)
        >>> logger.info("data_ingested", series_id="GDP", records=1000)
    """
    return structlog.get_logger(name)


# Initialize logging on module import
configure_logging()