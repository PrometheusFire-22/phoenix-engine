"""
Project Chronos: Configuration Management
=========================================
Purpose: Centralized, type-safe configuration using Pydantic
Pattern: 12-Factor App methodology (config via environment variables)
"""

from typing import Literal
from pathlib import Path
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    Application-wide configuration settings.
    
    All settings are loaded from environment variables or .env file.
    Pydantic ensures type safety and validation at startup.
    """
    
    # ========================================================================
    # Database Configuration
    # ========================================================================
    
    # Default host is 'timescaledb' for Docker networking
    # Override to 'localhost' in .env for local development
    database_host: str = Field(default="timescaledb", description="PostgreSQL host")
    database_port: int = Field(default=5432, ge=1, le=65535)
    
    # SECURITY: No defaults - these MUST be provided via .env
    database_name: str = Field(description="Database name (REQUIRED)")
    database_user: str = Field(description="Database user (REQUIRED)")
    database_password: str = Field(description="Database password (REQUIRED)")
    
    # Connection pool settings (institutional best practice)
    database_pool_size: int = Field(default=5, ge=1, le=50)
    database_max_overflow: int = Field(default=10, ge=0, le=100)
    database_pool_timeout: int = Field(default=30, ge=1)  # seconds
    
    @property
    def database_url(self) -> str:
        """
        Construct SQLAlchemy-compatible connection string.
        
        Returns:
            postgresql://user:password@host:port/dbname
        """
        return (
            f"postgresql://{self.database_user}:{self.database_password}"
            f"@{self.database_host}:{self.database_port}/{self.database_name}"
        )
    
    # ========================================================================
    # API Configuration
    # ========================================================================
    
    fred_api_key: str = Field(default="", description="FRED API key")
    
    # Rate limiting (requests per minute)
    fred_rate_limit: int = Field(default=120, ge=1)
    
    @field_validator("fred_api_key")
    @classmethod
    def validate_fred_key(cls, v: str) -> str:
        """Ensure FRED API key is set when needed."""
        if not v or v == "your_fred_api_key_here":
            raise ValueError(
                "FRED_API_KEY not set. Get one at: "
                "https://fred.stlouisfed.org/docs/api/api_key.html"
            )
        return v
    
    # ========================================================================
    # Logging Configuration
    # ========================================================================
    
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"
    log_format: Literal["json", "text"] = "json"
    
    # ========================================================================
    # Application Settings
    # ========================================================================
    
    environment: Literal["development", "staging", "production"] = "development"
    
    # Project root (useful for relative paths)
    project_root: Path = Field(
        default_factory=lambda: Path(__file__).parent.parent.parent.parent
    )
    
    # ========================================================================
    # Pydantic Settings Configuration
    # ========================================================================
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


# ============================================================================
# Global Settings Instance
# ============================================================================

def get_settings() -> Settings:
    """
    Factory function to get settings instance.
    
    This pattern allows for easy mocking in tests and lazy initialization.
    
    Returns:
        Validated Settings instance
        
    Raises:
        ValidationError: If required environment variables are missing/invalid
    """
    return Settings()


# Convenience export
settings = get_settings()