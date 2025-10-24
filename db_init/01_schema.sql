-- ============================================================================
-- Phoenix Engine V2.0 - Database Schema
-- ============================================================================
-- Purpose: Initialize core tables following "Transform-in-SQL" architecture
-- Principle: This schema stores RAW data only. All transformations in views.
-- ============================================================================

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ============================================================================
-- REFERENCE TABLES (Master Data)
-- ============================================================================

-- Sources: ETFs, Indices, or other company groupings
CREATE TABLE sources (
    source_id SERIAL PRIMARY KEY,
    source_name VARCHAR(50) UNIQUE NOT NULL,
    source_type VARCHAR(20) CHECK (source_type IN ('ETF', 'INDEX', 'CUSTOM')),
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sources_name ON sources(source_name);

-- Companies: Deduplicated master list of all companies
CREATE TABLE companies (
    company_id SERIAL PRIMARY KEY,
    ticker VARCHAR(20) UNIQUE NOT NULL,
    company_name VARCHAR(255) NOT NULL,
    sector VARCHAR(100),
    sub_sector VARCHAR(100),
    exchange VARCHAR(20),  -- e.g., 'KS' for Korea, 'TW' for Taiwan, 'NASDAQ'
    country_code CHAR(2),  -- ISO 3166-1 alpha-2 (KR, TW, HK, US)
    currency_code CHAR(3),  -- ISO 4217 (KRW, TWD, HKD, USD)
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_companies_ticker ON companies(ticker);
CREATE INDEX idx_companies_sector ON companies(sector);
CREATE INDEX idx_companies_sub_sector ON companies(sub_sector);
CREATE INDEX idx_companies_active ON companies(is_active);

-- Company-Source relationship (many-to-many)
CREATE TABLE company_sources (
    company_id INTEGER REFERENCES companies(company_id) ON DELETE CASCADE,
    source_id INTEGER REFERENCES sources(source_id) ON DELETE CASCADE,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (company_id, source_id)
);

CREATE INDEX idx_company_sources_company ON company_sources(company_id);
CREATE INDEX idx_company_sources_source ON company_sources(source_id);

-- ============================================================================
-- RAW DATA TABLES (Ingestion Layer - "Dumb" Storage)
-- ============================================================================

-- Raw Daily Market Data
-- Stores daily OHLCV data from yfinance with NO transformations
CREATE TABLE raw_daily_prices (
    ticker VARCHAR(20) NOT NULL,
    price_date DATE NOT NULL,
    open_price DECIMAL(20,4),
    high_price DECIMAL(20,4),
    low_price DECIMAL(20,4),
    close_price DECIMAL(20,4),
    adj_close_price DECIMAL(20,4),
    volume BIGINT,
    ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ticker, price_date)
);

-- Convert to TimescaleDB hypertable for efficient time-series queries
SELECT create_hypertable('raw_daily_prices', 'price_date', if_not_exists => TRUE);

CREATE INDEX idx_raw_daily_prices_ticker ON raw_daily_prices(ticker);

-- Raw Quarterly Financials (TTM values as provided by yfinance)
-- CRITICAL: This stores the RAW TTM data with NO discrete conversion
CREATE TABLE raw_financials (
    ticker VARCHAR(20) NOT NULL,
    fiscal_date DATE NOT NULL,  -- End date of the fiscal quarter
    report_period VARCHAR(10),  -- e.g., '2024Q3' for clarity
    
    -- Income Statement (TTM values from yfinance)
    total_revenue_ttm DECIMAL(20,2),
    cost_of_revenue_ttm DECIMAL(20,2),
    gross_profit_ttm DECIMAL(20,2),
    operating_income_ttm DECIMAL(20,2),
    net_income_ttm DECIMAL(20,2),
    ebitda_ttm DECIMAL(20,2),
    
    -- Balance Sheet (Point-in-time values)
    total_assets DECIMAL(20,2),
    total_liabilities DECIMAL(20,2),
    stockholders_equity DECIMAL(20,2),
    cash_and_equivalents DECIMAL(20,2),
    short_term_debt DECIMAL(20,2),
    long_term_debt DECIMAL(20,2),
    
    -- Cash Flow Statement (TTM values from yfinance)
    operating_cash_flow_ttm DECIMAL(20,2),
    capital_expenditure_ttm DECIMAL(20,2),
    free_cash_flow_ttm DECIMAL(20,2),
    
    -- Share data (Point-in-time)
    shares_outstanding BIGINT,
    
    ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ticker, fiscal_date)
);

-- Convert to TimescaleDB hypertable
SELECT create_hypertable('raw_financials', 'fiscal_date', if_not_exists => TRUE);

CREATE INDEX idx_raw_financials_ticker ON raw_financials(ticker);
CREATE INDEX idx_raw_financials_report_period ON raw_financials(report_period);

-- ============================================================================
-- INGESTION TRACKING & DATA QUALITY
-- ============================================================================

-- Ingestion Log: Track backfill runs and data freshness
CREATE TABLE ingestion_log (
    log_id SERIAL PRIMARY KEY,
    run_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    script_name VARCHAR(100),
    status VARCHAR(20) CHECK (status IN ('STARTED', 'SUCCESS', 'PARTIAL', 'FAILED')),
    tickers_processed INTEGER,
    tickers_failed INTEGER,
    records_inserted INTEGER,
    error_message TEXT,
    duration_seconds INTEGER,
    notes TEXT
);

CREATE INDEX idx_ingestion_log_timestamp ON ingestion_log(run_timestamp DESC);
CREATE INDEX idx_ingestion_log_status ON ingestion_log(status);

-- Data Quality Checks: Track issues found during ingestion
CREATE TABLE data_quality_issues (
    issue_id SERIAL PRIMARY KEY,
    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ticker VARCHAR(20),
    issue_type VARCHAR(50),  -- e.g., 'MISSING_TTM', 'NEGATIVE_REVENUE', 'STALE_DATA'
    severity VARCHAR(20) CHECK (severity IN ('INFO', 'WARNING', 'ERROR', 'CRITICAL')),
    description TEXT,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP
);

CREATE INDEX idx_dq_issues_ticker ON data_quality_issues(ticker);
CREATE INDEX idx_dq_issues_severity ON data_quality_issues(severity);
CREATE INDEX idx_dq_issues_resolved ON data_quality_issues(resolved);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for companies table
CREATE TRIGGER companies_updated_at
    BEFORE UPDATE ON companies
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- INITIAL COMMENTS & METADATA
-- ============================================================================

COMMENT ON TABLE sources IS 'Reference table for ETFs, indices, and other company groupings';
COMMENT ON TABLE companies IS 'Master list of all companies (deduplicated from master CSV)';
COMMENT ON TABLE company_sources IS 'Many-to-many relationship between companies and sources';
COMMENT ON TABLE raw_daily_prices IS 'RAW daily OHLCV data from yfinance (NO transformations)';
COMMENT ON TABLE raw_financials IS 'RAW quarterly TTM financials from yfinance (discrete conversion in views)';
COMMENT ON TABLE ingestion_log IS 'Tracks backfill script runs and success rates';
COMMENT ON TABLE data_quality_issues IS 'Logs data quality problems for monitoring';

-- ============================================================================
-- INITIAL DATA QUALITY VIEW (Preview)
-- ============================================================================

-- View to check data freshness
CREATE OR REPLACE VIEW v_data_freshness AS
SELECT 
    c.ticker,
    c.company_name,
    MAX(rdp.price_date) AS last_price_date,
    MAX(rf.fiscal_date) AS last_financial_date,
    CURRENT_DATE - MAX(rdp.price_date) AS days_since_price_update,
    CURRENT_DATE - MAX(rf.fiscal_date) AS days_since_financial_update,
    CASE 
        WHEN CURRENT_DATE - MAX(rdp.price_date) > 7 THEN 'STALE'
        WHEN CURRENT_DATE - MAX(rdp.price_date) > 3 THEN 'WARNING'
        ELSE 'FRESH'
    END AS price_data_status,
    CASE 
        WHEN CURRENT_DATE - MAX(rf.fiscal_date) > 120 THEN 'STALE'
        WHEN CURRENT_DATE - MAX(rf.fiscal_date) > 90 THEN 'WARNING'
        ELSE 'FRESH'
    END AS financial_data_status
FROM companies c
LEFT JOIN raw_daily_prices rdp ON c.ticker = rdp.ticker
LEFT JOIN raw_financials rf ON c.ticker = rf.ticker
WHERE c.is_active = TRUE
GROUP BY c.ticker, c.company_name
ORDER BY c.ticker;

COMMENT ON VIEW v_data_freshness IS 'Monitors data freshness for quality control';

-- ============================================================================
-- GRANTS (Security)
-- ============================================================================

-- Grant permissions to the application user (prometheus)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO prometheus;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO prometheus;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO prometheus;

-- ============================================================================
-- INITIALIZATION COMPLETE
-- ============================================================================

-- Log the schema initialization
INSERT INTO ingestion_log (script_name, status, notes)
VALUES ('01_schema.sql', 'SUCCESS', 'Database schema initialized successfully');

-- Success message
DO $$
BEGIN
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Phoenix Engine V2.0 - Schema Initialization Complete';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Tables created: sources, companies, company_sources';
    RAISE NOTICE 'Raw data tables: raw_daily_prices, raw_financials';
    RAISE NOTICE 'Monitoring tables: ingestion_log, data_quality_issues';
    RAISE NOTICE 'TimescaleDB hypertables: raw_daily_prices, raw_financials';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Next step: Run 02_views.sql to create transformation views';
    RAISE NOTICE '=================================================================';
END $$;