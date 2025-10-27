# Project Chronos: Macroeconomic Data Platform

Production-grade, multi-source time-series data platform for macroeconomic indicators.

## Architecture

- **Database:** PostgreSQL 16 + TimescaleDB
- **Language:** Python 3.11+
- **ORM:** SQLAlchemy 2.0
- **Sources:** FRED, ECB, BOE, Bank of Canada, OECD, IMF, World Bank, Eurostat

## Quick Start

### Prerequisites

- Docker Desktop
- Python 3.11+
- FRED API Key (free): https://fred.stlouisfed.org/docs/api/api_key.html

### Setup Steps

1. **Clone and configure**
```bash
   git clone <repo-url>
   cd project-chronos
   cp .env.example .env
   # Edit .env and add your FRED_API_KEY
```

2. **Start database**
```bash
   docker-compose up -d
   docker-compose ps  # Verify running
```

3. **Install Python dependencies**
```bash
   python -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
```

4. **Verify setup**
```bash
   python -c "from chronos.database.connection import verify_database_connection; verify_database_connection()"
```

5. **Run first ingestion**
```bash
   python src/scripts/ingest_fred.py --series GDP --series UNRATE
```

## Database Schema
```
metadata schema:
├── data_sources          # API source registry
├── series_metadata       # Time-series definitions
├── series_attributes     # Flexible metadata
└── ingestion_log         # Audit trail

timeseries schema:
└── economic_observations # Hypertable (partitioned by date)
```

## Usage Examples
```bash
# Ingest multiple series
python src/scripts/ingest_fred.py --series GDP --series UNRATE --series CPIAUCSL

# Ingest with date range
python src/scripts/ingest_fred.py --series GDP --start-date 2020-01-01

# Verify connection only
python src/scripts/ingest_fred.py --series GDP --verify-only
```

## Querying Data
```sql
-- Connect to database
docker-compose exec timescaledb psql -U chronos_user -d chronos_db

-- View available series
SELECT source_series_id, series_name, frequency 
FROM metadata.series_metadata;

-- Query recent observations
SELECT observation_date, value
FROM timeseries.economic_observations eo
JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
WHERE sm.source_series_id = 'GDP'
ORDER BY observation_date DESC
LIMIT 10;
```

## Project Structure
```
project-chronos/
├── database/
│   └── schema.sql
├── src/
│   ├── chronos/
│   │   ├── config/
│   │   ├── database/
│   │   ├── ingestion/
│   │   └── utils/
│   └── scripts/
├── tests/
├── docker-compose.yml
└── requirements.txt
```

## Development
```bash
# Run tests
pytest tests/

# Format code
black src/ tests/

# Access pgAdmin (optional)
docker-compose --profile tools up -d pgadmin
# http://localhost:5050
```

## License

Proprietary
