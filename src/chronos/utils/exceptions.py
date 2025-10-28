"""
Project Chronos: Custom Exception Classes
==========================================
Purpose: Domain-specific exceptions for better error handling
"""


class ChronosBaseException(Exception):
    """Base exception for all Chronos errors."""
    pass


class DatabaseConnectionError(ChronosBaseException):
    """Raised when database connection fails."""
    pass


class IngestionError(ChronosBaseException):
    """Base exception for data ingestion errors."""
    pass


class APIError(IngestionError):
    """Raised when external API calls fail."""
    
    def __init__(self, source: str, status_code: int = None, message: str = None):
        self.source = source
        self.status_code = status_code
        self.message = message or f"API error from {source}"
        super().__init__(self.message)


class DataValidationError(IngestionError):
    """Raised when ingested data fails validation."""
    pass


class RateLimitError(APIError):
    """Raised when API rate limit is exceeded."""
    pass