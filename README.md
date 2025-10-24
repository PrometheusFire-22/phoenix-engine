# 🔥 The Phoenix Engine V2.0

**A Real-Time Private Company Valuation Engine Using Public Market Comparables**

Portfolio-grade data application demonstrating advanced data engineering, financial analysis, and full-stack development for VC investors and FinTech professionals.

---

## 📋 Project Status: Phase 1 - Backend Foundation

**Current Session: 1 of 4 (Foundation Complete ✅)**

### ✅ Session 1 Complete
- [x] Docker Compose configuration with TimescaleDB & pgAdmin
- [x] Database schema with proper constraints and hypertables
- [x] Sample master company list (100+ global companies)
- [x] Initial data quality views
- [x] Environment configuration

### 🔄 Next Sessions
- [ ] **Session 2**: SQL transformation views (TTM-to-Discrete conversion)
- [ ] **Session 3**: Backfill script with robust error handling
- [ ] **Session 4**: Testing, validation, and documentation

---

## 🏗️ Architecture: "Transform-in-SQL"

### Core Principle
- **Ingestion Layer (Python)**: "Dumb" - Extract and Load raw data only
- **Transformation Layer (SQL)**: "Smart" - All business logic in PostgreSQL views
- **Application Layer (Streamlit)**: Display and interact with pre-calculated views

### Data Flow
```
Master CSV → backfill.py → PostgreSQL Raw Tables → views.sql → Calculated Views → analytics.py → Streamlit UI
```

---

## 🚀 Quick Start

### Prerequisites
- **Docker Desktop** (with Docker Compose)
- **Git**
- **Python 3.10+** (for future scripts)
- At least 4GB available RAM

### Step 1: Clone and Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd phoenix-engine

# Create your environment file
cp .env.example .env

# IMPORTANT: Edit .env with your actual credentials
nano .env  # or use your preferred editor
```

### Step 2: Configure Environment

Edit `.env` with your credentials:

```bash
POSTGRES_USER=prometheus
POSTGRES_PASSWORD=Zarathustra22!
POSTGRES_DB=phoenix_engine

PGADMIN_EMAIL=axiologycapital@gmail.com
PGADMIN_PASSWORD=Zarathustra22!

DATABASE_URL=postgresql://prometheus:Zarathustra22!@timescaledb:5432/phoenix_engine
```

**⚠️ Security Note**: The credentials shown above are examples. Use strong, unique passwords in production.

### Step 3: Launch the Database

```bash
# Start the services
docker-compose up -d

# Verify services are running
docker-compose ps

# Expected output:
# phoenix_timescaledb   running   0.0.0.0:5432->5432/tcp
# phoenix_pgadmin       running   0.0.0.0:5050->80/tcp
```

### Step 4: Verify Database Initialization

```bash
# Check TimescaleDB logs
docker-compose logs timescaledb | tail -20

# You should see:
# "Phoenix Engine V2.0 - Schema Initialization Complete"
```

### Step 5: Access pgAdmin

1. Open browser: `http://localhost:5050`
2. Login with your `PGADMIN_EMAIL` and `PGADMIN_PASSWORD`
3. Add a new server:
   - **Name**: Phoenix Engine
   - **Host**: `timescaledb`
   - **Port**: `5432`
   - **Username**: `prometheus`
   - **Password**: Your `POSTGRES_PASSWORD`

### Step 6: Test the Database

Run these SQL queries in pgAdmin to verify setup:

```sql
-- Check that tables were created
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;

-- Expected output:
-- companies
-- company_sources
-- data_quality_issues
-- ingestion_log
-- raw_daily_prices
-- raw_financials
-- sources

-- Check initial ingestion log
SELECT * FROM ingestion_log;

-- Check data freshness view
SELECT * FROM v_data_freshness LIMIT 5;
```

---

## 📁 Project Structure

```
phoenix-engine/
├── docker-compose.yml          # Docker orchestration
├── .env                        # Environment variables (not in git)
├── .env.example               # Template for environment setup
├── .gitignore                 # Git ignore rules
├── README.md                  # This file
│
├── data/
│   └── master_company_list.csv  # Source of truth (100+ companies)
│
├── db_init/
│   ├── 01_schema.sql          # Database schema (✅ Complete)
│   ├── 02_views.sql           # Transformation views (🔄 Session 2)
│   └── 03_functions.sql       # Helper functions (🔄 Session 2)
│
├── src/
│   ├── backfill.py            # Ingestion script (🔄 Session 3)
│   ├── analytics.py           # Query wrapper (Phase 2)
│   └── app.py                 # Streamlit UI (Phase 2)
│
├── tests/
│   └── test_backfill.py       # Unit tests (🔄 Session 4)
│
└── requirements.txt           # Python dependencies (🔄 Session 3)
```

---

## 📊 Database Schema Overview

### Reference Tables
- **`sources`**: ETFs, indices (ARKK, FINX, AIQ, CLOU, ARKF)
- **`companies`**: Master list of 100+ companies (deduplicated)
- **`company_sources`**: Many-to-many relationships

### Raw Data Tables (TimescaleDB Hypertables)
- **`raw_daily_prices`**: Daily OHLCV data from yfinance
- **`raw_financials`**: Quarterly TTM financials (NO transformations yet)

### Monitoring Tables
- **`ingestion_log`**: Tracks backfill runs and success rates
- **`data_quality_issues`**: Logs data problems for monitoring

### Key Design Decisions

1. **Multi-Market Support**: Built-in fields for `exchange`, `country_code`, `currency_code`
   - US: NASDAQ, NYSE (USD)
   - Korea: KS exchange (KRW)
   - Taiwan: TW exchange (TWD)
   - Hong Kong: HK exchange (HKD)
   - Europe: Amsterdam (EUR)

2. **TimescaleDB Hypertables**: Efficient time-series queries on price and financial data

3. **Data Quality First**: Built-in freshness monitoring and issue tracking

4. **Raw Data Integrity**: No transformations at ingestion - all business logic in views

---

## 🔍 Master Company List

The `data/master_company_list.csv` is your **source of truth** with 100+ companies across:

### Sectors Covered
- **Enterprise Software**: CrowdStrike, Snowflake, ServiceNow, Datadog
- **FinTech**: Stripe, Adyen, Block, PayPal, Nu Holdings
- **Deep Tech / Hardware**: NVIDIA, ASML, Apple, TSMC, SK Hynix
- **E-commerce**: Amazon, Shopify, Airbnb, MercadoLibre
- **Digital Media**: Meta, Netflix, Spotify, Roblox
- **AI & Data**: Palantir, C3.ai, Snowflake

### Global Coverage
- **US**: 85+ companies
- **South Korea**: Samsung, SK Hynix
- **Taiwan**: TSMC, Acer, Advantech
- **Hong Kong**: Linklogis
- **Netherlands**: ASML, Adyen
- **Australia**: Flight Centre

### CSV Format
```csv
ticker,company_name,sector,sub_sector,source_name
CRWD,CrowdStrike Holdings Inc.,Enterprise Software,Cybersecurity,CLOU
CRWD,CrowdStrike Holdings Inc.,Enterprise Software,Cybersecurity,AIQ
```

**Note**: Companies can appear multiple times if they belong to multiple ETFs/indices.

---

## 🛠️ Common Operations

### Start/Stop Services

```bash
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# Stop and remove volumes (⚠️ deletes all data)
docker-compose down -v

# Restart a specific service
docker-compose restart timescaledb

# View logs
docker-compose logs -f timescaledb
docker-compose logs -f pgadmin
```

### Database Operations

```bash
# Connect to PostgreSQL via CLI
docker exec -it phoenix_timescaledb psql -U prometheus -d phoenix_engine

# Backup database
docker exec phoenix_timescaledb pg_dump -U prometheus phoenix_engine > backup.sql

# Restore database
docker exec -i phoenix_timescaledb psql -U prometheus phoenix_engine < backup.sql

# Check database size
docker exec phoenix_timescaledb psql -U prometheus -d phoenix_engine -c "
SELECT 
    pg_size_pretty(pg_database_size('phoenix_engine')) AS database_size;
"
```

### Useful SQL Queries

```sql
-- Check row counts for all tables
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    n_live_tup AS row_count
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- View data freshness
SELECT * FROM v_data_freshness WHERE price_data_status != 'FRESH';

-- Check ingestion history
SELECT 
    run_timestamp,
    script_name,
    status,
    tickers_processed,
    duration_seconds
FROM ingestion_log
ORDER BY run_timestamp DESC
LIMIT 10;

-- Find data quality issues
SELECT 
    ticker,
    issue_type,
    severity,
    description
FROM data_quality_issues
WHERE resolved = FALSE
ORDER BY severity, detected_at DESC;
```

---

## 🧪 Testing the Setup

Run this comprehensive test to verify everything works:

```sql
-- Test 1: Check TimescaleDB extension
SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';
-- Expected: timescaledb | 2.x.x

-- Test 2: Verify hypertables
SELECT hypertable_name, num_dimensions 
FROM timescaledb_information.hypertables;
-- Expected: raw_daily_prices, raw_financials

-- Test 3: Check table structure
\d companies
-- Should show: company_id, ticker, company_name, sector, sub_sector, etc.

-- Test 4: Verify indexes
SELECT indexname, tablename 
FROM pg_indexes 
WHERE schemaname = 'public' 
ORDER BY tablename, indexname;

-- Test 5: Test trigger
UPDATE companies SET company_name = 'Test Update' WHERE ticker = 'AAPL';
SELECT updated_at FROM companies WHERE ticker = 'AAPL';
-- Should show current timestamp
ROLLBACK;  -- Undo the test update
```

---

## 🚨 Troubleshooting

### Issue: Services won't start

```bash
# Check if ports are already in use
lsof -i :5432  # PostgreSQL
lsof -i :5050  # pgAdmin

# Kill processes using these ports, then restart
docker-compose down
docker-compose up -d
```

### Issue: Can't connect to database

```bash
# Check service health
docker-compose ps

# View detailed logs
docker-compose logs timescaledb

# Ensure database is ready
docker exec phoenix_timescaledb pg_isready -U prometheus
```

### Issue: pgAdmin won't connect to database

- **Host**: Must be `timescaledb` (container name), not `localhost`
- **Port**: `5432`
- **User**: Check your `.env` file
- **Password**: Must match `.env` exactly

### Issue: Schema didn't initialize

```bash
# Check if initialization scripts ran
docker-compose logs timescaledb | grep "Phoenix Engine"

# Manually run schema script
docker exec -i phoenix_timescaledb psql -U prometheus -d phoenix_engine < db_init/01_schema.sql
```

---

## 🎯 What's Next: Session 2

In the next session, we'll build the "Smart" transformation layer:

### SQL Views to Create
1. **`v_discrete_financials`**: Convert TTM → Discrete quarterly values
2. **`v_clean_ttm_metrics`**: Re-calculate clean TTM from discrete
3. **`v_company_valuation_metrics`**: Final view with all calculated metrics
   - Revenue growth rates
   - Rule of 40
   - EV/Revenue multiples
   - Free cash flow metrics
   - SaaS Magic Number

### Key SQL Techniques
- Window functions (`LAG`, `LEAD`)
- Robust date-based JOINs
- NULL handling strategies
- Performance optimization with materialized views

---

## 📚 Resources

### yfinance API
- **Tickers**: Must match Yahoo Finance exactly (e.g., `000660.KS` for Korean stocks)
- **TTM Data**: Trailing-Twelve-Month values provided automatically
- **Limitations**: Free API with rate limits, historical data may have gaps

### TimescaleDB
- [Documentation](https://docs.timescale.com/)
- [Hypertables Guide](https://docs.timescale.com/use-timescale/latest/hypertables/)

### PostgreSQL
- [Window Functions](https://www.postgresql.org/docs/current/tutorial-window.html)
- [Views and Materialized Views](https://www.postgresql.org/docs/current/sql-createview.html)

---

## 🤝 Contributing

This is a portfolio project, but suggestions are welcome:
- Open an issue for bugs or enhancements
- Fork and submit pull requests
- Share feedback on architecture decisions

---

## 📄 License

MIT License - See LICENSE file for details

---

## 👤 Author

**Your Name**
- Portfolio: [your-portfolio-url]
- LinkedIn: [your-linkedin]
- GitHub: [your-github]

---

## 🏆 Project Goals

This application demonstrates:
- ✅ Advanced SQL transformation patterns
- ✅ Time-series database optimization
- ✅ Financial metric calculation
- ✅ Multi-market data handling
- ✅ Data quality monitoring
- 🔄 Full-stack development (Phase 2)
- 🔄 Interactive data visualization (Phase 2)
- 🔄 Production-ready deployment (Phase 2)

---

**Status**: 🟢 Backend Foundation Complete - Ready for Session 2

**Last Updated**: October 2025