# Project Chronos: Macroeconomic Data Platform

> Production-grade, multi-source time-series data platform for institutional-quality macroeconomic analysis.

## 🎯 Current Status

✅ **Phase 1 Complete:** FRED API integration operational  
🚧 **Phase 2 In Progress:** Bank of Canada Valet API  
📋 **Phase 3 Planned:** ECB, OECD, IMF integrations  

### Data Inventory (As of Latest Commit)

| Source | Series Count | Observations | Date Range |
|--------|--------------|--------------|------------|
| FRED (U.S.) | 14 | ~12,000+ | 1947-2024 |
| Bank of Canada | 0 | 0 | Ready to ingest |

---

## 🚀 Quick Start

### Prerequisites
- Docker Desktop
- Python 3.11+
- FRED API Key ([get free key](https://fred.stlouisfed.org/docs/api/api_key.html))

### Setup (5 minutes)
```bash
# 1. Clone repository
git clone <repo-url>
cd project-chronos

# 2. Configure environment
cp .env.example .env
# Edit .env and add your FRED_API_KEY

# 3. Start database
docker compose up -d

# 4. Create Python environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 5. Set Python path
export PYTHONPATH="${PYTHONPATH}:$(pwd)/src"

# 6. Run first ingestion
python src/scripts/ingest_fred.py --series GDP
```

---

## 📊 Usage Examples

### Ingest Economic Data
```bash
# Single series
python src/scripts/ingest_fred.py --series GDP

# Multiple series
python src/scripts/ingest_fred.py --series GDP --series UNRATE --series CPIAUCSL

# With date range
python src/scripts/ingest_fred.py --series GDP --start-date 2020-01-01

# Bank of Canada data
python src/scripts/ingest_valet.py --series FXUSDCAD
```

### Query Data (SQL)
```sql
-- Connect to database
docker compose exec timescaledb psql -U prometheus -d chronos_db

-- View all available series
SELECT source_series_id, series_name FROM metadata.series_metadata;

-- Get latest GDP data
SELECT observation_date, value
FROM timeseries.economic_observations eo
JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
WHERE sm.source_series_id = 'GDP'
ORDER BY observation_date DESC
LIMIT 10;

### Export Data (Python)
```python
import pandas as pd
from sqlalchemy import create_engine

# Connect to database
engine = create_engine('postgresql://prometheus:Zarathustra22!@localhost:5432/chronos_db')

# Load GDP data
df = pd.read_sql("""
    SELECT observation_date, value
    FROM timeseries.economic_observations eo
    JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
    WHERE sm.source_series_id = 'GDP'
    ORDER BY observation_date
""", engine)

# Analyze
print(df.describe())
df.to_csv('gdp_data.csv', index=False)
```

---

## 🏗️ Architecture

### System Design
```
External APIs → Python Ingestors → PostgreSQL/TimescaleDB
(FRED, Valet)   (src/scripts/)     (Docker container)
                                    │
                                    ├─ metadata schema (definitions)
                                    └─ timeseries schema (observations)
```

### Database Schema

**Metadata Schema:**
- `data_sources` - API registry (FRED, Valet, etc.)
- `series_metadata` - Time-series definitions
- `series_attributes` - Flexible key-value metadata
- `ingestion_log` - Audit trail

**Timeseries Schema:**
- `economic_observations` - TimescaleDB hypertable (partitioned by date)

**Key Design Decisions:**
- ✅ **Multi-source support:** Multiple APIs can provide same metric
- ✅ **Data lineage:** Full audit trail from source to storage
- ✅ **Idempotency:** Re-running ingestion is safe (upserts)
- ✅ **Time-series optimization:** Automatic partitioning for fast queries

---

## 📁 Project Structure
```
project-chronos/
├── database/
│   └── schema.sql              # Database schema definition
├── docs/
│   ├── USER_GUIDE.md           # Comprehensive user manual
│   └── architecture.md         # Technical architecture docs
├── src/
│   ├── chronos/
│   │   ├── config/
│   │   │   └── settings.py     # Configuration management
│   │   ├── database/
│   │   │   └── connection.py   # SQLAlchemy connection pool
│   │   ├── ingestion/
│   │   │   ├── base.py         # Abstract base ingestor
│   │   │   ├── fred.py         # FRED API implementation
│   │   │   └── valet.py        # Bank of Canada implementation
│   │   └── utils/
│   │       ├── logging.py      # Structured logging
│   │       └── exceptions.py   # Custom exceptions
│   └── scripts/
│       ├── ingest_fred.py      # FRED ingestion CLI
│       └── ingest_valet.py     # Valet ingestion CLI
├── tests/
│   ├── unit/                   # Unit tests
│   └── integration/            # Integration tests
├── .env                        # Environment variables (not in Git)
├── .env.example               # Template for .env
├── docker-compose.yml         # Docker services definition
└── requirements.txt           # Python dependencies
```

---

## 🔧 Configuration

### Environment Variables (`.env`)
```bash
# Database (required)
DATABASE_HOST=localhost         # Use 'timescaledb' for Docker networking
DATABASE_PORT=5432
DATABASE_NAME=chronos_db
DATABASE_USER=prometheus
DATABASE_PASSWORD=your_password

# API Keys (required)
FRED_API_KEY=your_api_key_here

# Optional
LOG_LEVEL=INFO
LOG_FORMAT=json
ENVIRONMENT=development
```

### Docker Services
```bash
# Start all services
docker compose up -d

# Start with pgAdmin (web UI)
docker compose --profile tools up -d

# View logs
docker compose logs -f timescaledb

# Stop services
docker compose down
```

---

## 📚 Available Data Series

### FRED (Federal Reserve Economic Data)

**Currently Ingested:**
- `GDP` - Gross Domestic Product
- `GDPC1` - Real Gross Domestic Product
- `UNRATE` - Unemployment Rate
- `CPIAUCSL` - Consumer Price Index for All Urban Consumers
- `CPILFESL` - CPI for All Urban Consumers: Less Food & Energy
- `FEDFUNDS` - Federal Funds Effective Rate
- `DGS10` - 10-Year Treasury Constant Maturity Rate
- `DEXUSEU` - U.S. / Euro Foreign Exchange Rate
- `DEXUSUK` - U.S. / U.K. Foreign Exchange Rate
- `DEXCAUS` - Canada / U.S. Foreign Exchange Rate
- `PAYEMS` - All Employees: Total Nonfarm Payrolls
- `INDPRO` - Industrial Production Index
- `HOUST` - Housing Starts: Total New Privately Owned
- `UMCSENT` - University of Michigan: Consumer Sentiment

**Find More Series:** https://fred.stlouisfed.org/

### Bank of Canada (Valet API)

**Common Series:**
- `FXUSDCAD` - USD/CAD exchange rate (daily)
- `FXEURCAD` - EUR/CAD exchange rate (daily)
- `STATIC_CPILFESL` - CPI excluding food and energy
- `IEXE0124` - GDP at market prices (expenditure-based)

**API Documentation:** https://www.bankofcanada.ca/valet/docs

---

## 🛠️ Development

### Running Tests
```bash
# All tests
pytest tests/

# With coverage
pytest tests/ --cov=src/chronos --cov-report=html

# Specific test file
pytest tests/unit/test_connection.py -v
```

### Code Quality
```bash
# Format code
black src/ tests/

# Lint code
ruff check src/ tests/

# Type checking (if using mypy)
mypy src/
```

### Adding a New Data Source

1. Create ingestor class in `src/chronos/ingestion/`:
```python
from chronos.ingestion.base import BaseIngestor

class NewSourceIngestor(BaseIngestor):
    def __init__(self, session):
        super().__init__(session, source_name="NEW_SOURCE")
    
    def fetch_series_metadata(self, series_ids):
        # Implement API-specific logic
        pass
    
    def fetch_observations(self, series_id, start_date, end_date):
        # Implement API-specific logic
        pass
```

2. Add source to database:
```sql
INSERT INTO metadata.data_sources (source_name, api_type, base_url, requires_auth)
VALUES ('NEW_SOURCE', 'rest', 'https://api.example.com', FALSE);
```

3. Create ingestion script in `src/scripts/ingest_newsource.py`

4. Test thoroughly before committing

---

## 📖 Documentation

- **[User Guide](docs/USER_GUIDE.md)** - Comprehensive usage instructions
- **[Architecture](docs/architecture.md)** - Technical design decisions
- **[API Guides](docs/api_guides/)** - Per-source API documentation

---

## 🐛 Troubleshooting

### Common Issues

**"ModuleNotFoundError: No module named 'chronos'"**
```bash
export PYTHONPATH="${PYTHONPATH}:$(pwd)/src"
```

**"connection refused"**
```bash
docker compose ps  # Check if database is running
docker compose up -d  # Start if stopped
```

**"FRED_API_KEY not set"**
- Ensure `.env` file exists and has real API key
- Get free key: https://fred.stlouisfed.org/docs/api/api_key.html

**No data after ingestion**
```sql
-- Check ingestion log
SELECT * FROM metadata.ingestion_log ORDER BY log_id DESC LIMIT 5;

-- Check series was registered
SELECT * FROM metadata.series_metadata WHERE source_series_id = 'YOUR_SERIES';

-- Check observations
SELECT COUNT(*) FROM timeseries.economic_observations eo
JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
WHERE sm.source_series_id = 'YOUR_SERIES';
```

---

## 🗺️ Roadmap

### Phase 2: Additional Data Sources
- [ ] Bank of Canada Valet API (in testing)
- [ ] European Central Bank (ECB)
- [ ] OECD Statistics
- [ ] IMF Data Services
- [ ] World Bank API

### Phase 3: Analytics Layer
- [ ] Data validation framework
- [ ] Correlation analysis tools
- [ ] Growth rate calculations
- [ ] Seasonal adjustment utilities
- [ ] Forecasting models (ARIMA, Prophet)

### Phase 4: Visualization & Export
- [ ] Streamlit dashboard
- [ ] Plotly interactive charts
- [ ] Excel/CSV export utilities
- [ ] REST API for data access
- [ ] Grafana integration

### Phase 5: Production Hardening
- [ ] Airflow orchestration
- [ ] Automated testing (CI/CD)
- [ ] Data quality monitoring
- [ ] Alerting on ingestion failures
- [ ] Backup and disaster recovery

---

## 📄 License

Proprietary - All Rights Reserved

---

## 🙏 Acknowledgments

- **Federal Reserve Economic Data (FRED)** - Primary U.S. economic data
- **Bank of Canada** - Canadian economic and financial data
- **TimescaleDB** - Time-series database optimization
- **SQLAlchemy** - Python database toolkit

---

## 📞 Support

For questions or issues:
1. Check [User Guide](docs/USER_GUIDE.md)
2. Review [Troubleshooting](#troubleshooting) section
3. Check ingestion logs: `SELECT * FROM metadata.ingestion_log ORDER BY log_id DESC;`

---

**Built with institutional-grade best practices for hedge funds, PE firms, and financial analysts.**

STILL NEED TO UPDATE BY GETTING COMPLETE, UPDATED DOC FROM CLAUDE TOMORROW 
