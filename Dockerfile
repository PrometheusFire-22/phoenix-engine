# ============================================================================
# Phoenix Engine V2.0 - Application Dockerfile
# ============================================================================
# Purpose: Containerize Python backfill script and future Streamlit app
# Usage: Built automatically by docker-compose
# ============================================================================

FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first (layer caching optimization)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code and data
COPY src/ ./src/
COPY data/ ./data/

# Set Python path
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# Default command (can be overridden in docker-compose)
CMD ["python", "src/backfill.py"]