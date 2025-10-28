# Project Chronos: Macroeconomic Data Platform

> Production-grade, multi-source time-series data platform for institutional-quality macroeconomic analysis.

## 🎯 Project Status

| Phase | Status | Components |
|-------|--------|------------|
| Phase 1 | ✅ Complete | FRED API (14 series, 12,000+ obs) |
| Phase 2 | ✅ Complete | Bank of Canada Valet API (4 series, 8,800+ obs) |
| Phase 3 | 📋 Planned | ECB, OECD, IMF, World Bank APIs |
| Phase 4 | 📋 Planned | Analytics layer, forecasting, dashboards |

---

## 🚀 Quick Start (5 Minutes)

### Prerequisites

- Docker Desktop
- Python 3.11+
- FRED API Key ([get free here](https://fred.stlouisfed.org/docs/api/api_key.html))

### Installation
```bash
# 1. Clone and navigate
git clone <your-repo>
cd project-chronos

# 2. Configure environment
cp .env.example .env
# Edit .env: Add your FRED_API_KEY

# 3. Start database
docker compose up -d

# 4. Setup Python
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
export PYTHONPATH="${PYTHONPATH}:$(pwd)/src"

# 5. Initialize database views
cat database/views.sql | docker compose exec -T timescaledb psql -U prometheus -d chronos_db

# 6. Test ingestion
python src/scripts/ingest_fred.py --series GDP
```

---

## 📊 Usage Examples

### Data Ingestion
```bash
# FRED: U.S. economic data
python src/scripts/ingest_fred.py --series GDP --series UNRATE

# Bank of Canada: FX rates and economic data
python src/scripts/ingest_valet.py --series FXUSDCAD --series FXEURCAD

# With date range
python src/scripts/ingest_fred.py --series GDP --start-date 2020-01-01
```

### SQL Queries
```bash
# Connect to database
docker compose exec timescaledb psql -U prometheus -d chronos_db
```
```sql
-- List all series
SELECT source_series_id, series_name, frequency 
FROM metadata.series_metadata;

-- Latest GDP
SELECT observation_date, value 
FROM timeseries.economic_observations eo
JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
WHERE sm.source_series_id = 'GDP'
ORDER BY observation_date DESC LIMIT 10;

-- Normalized FX rates (all in USD per 1 FX)
SELECT observation_date, source_series_id, usd_per_fx
FROM analytics.fx_rates_normalized
WHERE observation_date >= '2024-01-01'
ORDER BY observation_date DESC LIMIT 10;

-- Data quality check
SELECT * FROM analytics.data_quality_dashboard;
```

### Python Analysis
```python
import pandas as pd
from sqlalchemy import create_engine

engine = create_engine('postgresql://user:pass@localhost:5432/chronos_db')

# Load data
df = pd.read_sql("""
    SELECT observation_date, value
    FROM timeseries.economic_observations eo
    JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
    WHERE sm.source_series_id = 'GDP'
""", engine)

df.plot(x='observation_date', y='value')
```

---

## 🏗️ Architecture

### Three-Layer Data Model
```
Layer 1: Raw Storage          Layer 2: Normalized Views      Layer 3: Analytics
━━━━━━━━━━━━━━━━━━━━━━━━━    ━━━━━━━━━━━━━━━━━━━━━━━━━━━    ━━━━━━━━━━━━━━━━━
economic_observations    →    fx_rates_normalized       →    Python/Jupyter
(immutable, as-is)            (standardized units)           (forecasting, viz)
```

### Database Schema
```
chronos_db/
├── metadata/
│   ├── data_sources          # API registry
│   ├── series_metadata       # Time-series definitions
│   ├── series_attributes     # Key-value metadata
│   └── ingestion_log         # Audit trail
├── timeseries/
│   └── economic_observations # Hypertable (1-year chunks)
└── analytics/
    ├── fx_rates_normalized
    ├── macro_indicators_latest
    └── data_quality_dashboard
```

---

## 📁 Project Structure
```
project-chronos/
├── database/
│   ├── schema.sql              # Core schema
│   └── views.sql               # Analytical views
├── docs/
│   ├── USER_GUIDE.md
│   ├── SCHEMA_REFERENCE.md
│   └── DATA_QUALITY_CHECKLIST.md
├── src/
│   ├── chronos/
│   │   ├── config/settings.py
│   │   ├── database/connection.py
│   │   ├── ingestion/
│   │   │   ├── base.py
│   │   │   ├── fred.py
│   │   │   └── valet.py
│   │   └── utils/
│   └── scripts/
│       ├── ingest_fred.py
│       └── ingest_valet.py
└── tests/
```

---

## 🔧 Configuration

### Environment Variables (.env)
```bash
DATABASE_HOST=localhost
DATABASE_NAME=chronos_db
DATABASE_USER=your_user
DATABASE_PASSWORD=your_password
FRED_API_KEY=your_api_key
LOG_LEVEL=INFO
ENVIRONMENT=development
```

---

## 📚 Available Data

### FRED (U.S. Federal Reserve)

- GDP, GDPC1 - Gross Domestic Product
- UNRATE - Unemployment Rate
- CPIAUCSL, CPILFESL - Inflation indicators
- FEDFUNDS, DGS10 - Interest rates
- DEXUSEU, DEXUSUK, DEXCAUS - FX rates
- PAYEMS - Nonfarm Payrolls
- INDPRO - Industrial Production
- HOUST - Housing Starts
- UMCSENT - Consumer Sentiment

### Bank of Canada

- FXUSDCAD, FXEURCAD, FXGBPCAD, FXJPYCAD - Exchange rates
- V122530 - Policy interest rate
- More at: https://www.bankofcanada.ca/valet/docs

---

## 🛠️ Development

### Running Tests
```bash
pytest tests/ --cov=src/chronos
```

### Code Quality
```bash
black src/ tests/
ruff check src/ tests/
```

### Adding New Data Sources

1. Create `src/chronos/ingestion/newsource.py`
2. Inherit from `BaseIngestor`
3. Implement `fetch_series_metadata()` and `fetch_observations()`
4. Create `src/scripts/ingest_newsource.py`
5. Add source to `metadata.data_sources`

---

## 📖 Documentation

- [User Guide](docs/USER_GUIDE.md) - Comprehensive instructions
- [Schema Reference](docs/SCHEMA_REFERENCE.md) - Database documentation
- [Data Quality](docs/DATA_QUALITY_CHECKLIST.md) - QA procedures

---

## 🐛 Troubleshooting

### Module Not Found
```bash
export PYTHONPATH="${PYTHONPATH}:$(pwd)/src"
```

### Connection Refused
```bash
docker compose ps
docker compose up -d
```

### FRED API Key Error

Ensure `.env` has real key (not placeholder)

### Stale Data

Check frequency-aware staleness:
```sql
SELECT * FROM analytics.data_quality_dashboard 
WHERE freshness_status LIKE '🔴%';
```

---

## 🗺️ Roadmap

### Phase 3: Additional Sources
- [ ] European Central Bank (ECB)
- [ ] OECD Statistics
- [ ] IMF Data Services
- [ ] World Bank API

### Phase 4: Analytics
- [ ] Growth rate calculations
- [ ] Correlation analysis
- [ ] ARIMA forecasting
- [ ] Seasonal adjustment

### Phase 5: Visualization
- [ ] Streamlit dashboard
- [ ] Plotly charts
- [ ] Grafana integration
- [ ] REST API

---

## 📄 License

Proprietary - All Rights Reserved

---

## 🙏 Acknowledgments

Built with institutional-grade practices for hedge funds and financial analysts.

- Federal Reserve Economic Data (FRED)
- Bank of Canada Valet API
- TimescaleDB
- PostgreSQL
- SQLAlchemy