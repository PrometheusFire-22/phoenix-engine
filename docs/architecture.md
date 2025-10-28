# Project Chronos: Architecture Documentation

## Overview

Project Chronos is a production-grade macroeconomic data platform designed to ingest, store, and serve time-series data from multiple authoritative sources.

## Design Principles

### 1. Source-Agnostic Design
- Each data source registers series with unique identifiers
- Multiple sources can provide data for the same economic concept
- No data loss from source-specific transformations

### 2. Temporal Partitioning
- TimescaleDB hypertables partition data by observation_date
- Optimized for time-range queries (last N years, specific quarters)
- Automatic compression for historical data

### 3. Audit Trail
- Every ingestion logged with timestamps and results
- Idempotent operations (re-running is safe)
- Full data lineage from source to storage

## Database Schema

### Metadata Schema
- `data_sources`: API registry
- `series_metadata`: Time-series definitions
- `series_attributes`: Flexible key-value metadata
- `ingestion_log`: Operational audit trail

### Timeseries Schema
- `economic_observations`: Hypertable storing all observations
- Composite primary key: (series_id, observation_date)
- Partitioned by observation_date for query performance

## Data Flow
```
External API → Ingestor → series_metadata → economic_observations
                     ↓
              ingestion_log
```

## Extending the Platform

### Adding New Data Sources

1. Create ingestor class inheriting from `BaseIngestor`
2. Implement `fetch_series_metadata()` and `fetch_observations()`
3. Register source in `metadata.data_sources`
4. Create ingestion script in `src/scripts/`

### Example: Adding ECB Data
```python
from chronos.ingestion.base import BaseIngestor

class ECBIngestor(BaseIngestor):
    def __init__(self, session):
        super().__init__(session, source_name="ECB_SDW")
    
    def fetch_series_metadata(self, series_ids):
        # ECB-specific API logic
        pass
    
    def fetch_observations(self, series_id, start_date, end_date):
        # ECB-specific API logic
        pass
```

## Performance Considerations

- **Connection pooling**: 5 base connections, 10 overflow
- **Rate limiting**: Respects per-source API limits
- **Batch inserts**: Uses bulk upserts for observations
- **Indexes**: Optimized for time-range and series lookups

## Security

- API keys stored in environment variables
- Database credentials not in version control
- Statement timeout prevents runaway queries (5 minutes)
- Read-only views for analytics queries