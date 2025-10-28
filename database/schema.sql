-- ============================================================================
-- Project Chronos: Database Schema Definition
-- Version: 1.0.0 (MVP)
-- Target: PostgreSQL 15+ with TimescaleDB 2.11+
-- ============================================================================

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ============================================================================
-- METADATA SCHEMA
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS metadata;

-- ----------------------------------------------------------------------------
-- Table: data_sources
-- ----------------------------------------------------------------------------
CREATE TABLE metadata.data_sources (
    source_id       SERIAL PRIMARY KEY,
    source_name     VARCHAR(100) UNIQUE NOT NULL,
    api_type        VARCHAR(50) NOT NULL,
    base_url        TEXT NOT NULL,
    requires_auth   BOOLEAN DEFAULT FALSE,
    is_active       BOOLEAN DEFAULT TRUE,
    rate_limit_rpm  INTEGER,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_data_sources_active ON metadata.data_sources(is_active) WHERE is_active = TRUE;

-- ----------------------------------------------------------------------------
-- Table: series_metadata
-- ----------------------------------------------------------------------------
CREATE TABLE metadata.series_metadata (
    series_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id           INTEGER NOT NULL REFERENCES metadata.data_sources(source_id),
    source_series_id    VARCHAR(255) NOT NULL,
    series_name         TEXT NOT NULL,
    series_description  TEXT,
    frequency           VARCHAR(20),
    units               VARCHAR(100),
    seasonal_adjustment VARCHAR(50),
    geography           VARCHAR(100),
    last_updated        TIMESTAMPTZ,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(source_id, source_series_id)
);

CREATE INDEX idx_series_source ON metadata.series_metadata(source_id);
CREATE INDEX idx_series_geography ON metadata.series_metadata(geography);
CREATE INDEX idx_series_frequency ON metadata.series_metadata(frequency);
CREATE INDEX idx_series_active ON metadata.series_metadata(is_active) WHERE is_active = TRUE;

-- ----------------------------------------------------------------------------
-- Table: series_attributes
-- ----------------------------------------------------------------------------
CREATE TABLE metadata.series_attributes (
    attribute_id    SERIAL PRIMARY KEY,
    series_id       UUID NOT NULL REFERENCES metadata.series_metadata(series_id) ON DELETE CASCADE,
    attribute_key   VARCHAR(100) NOT NULL,
    attribute_value TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(series_id, attribute_key)
);

CREATE INDEX idx_series_attributes_lookup ON metadata.series_attributes(series_id, attribute_key);

-- ============================================================================
-- TIMESERIES SCHEMA
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS timeseries;

-- ----------------------------------------------------------------------------
-- Table: economic_observations (HYPERTABLE)
-- ----------------------------------------------------------------------------
CREATE TABLE timeseries.economic_observations (
    series_id           UUID NOT NULL REFERENCES metadata.series_metadata(series_id),
    observation_date    DATE NOT NULL,
    value               NUMERIC(20,6),
    value_status        VARCHAR(20),
    source_id           INTEGER NOT NULL REFERENCES metadata.data_sources(source_id),
    ingestion_timestamp TIMESTAMPTZ DEFAULT NOW(),
    
    PRIMARY KEY (series_id, observation_date)
);

-- Convert to TimescaleDB hypertable
SELECT create_hypertable(
    'timeseries.economic_observations',
    'observation_date',
    chunk_time_interval => INTERVAL '1 year',
    if_not_exists => TRUE
);

CREATE INDEX idx_obs_series_date ON timeseries.economic_observations(series_id, observation_date DESC);
CREATE INDEX idx_obs_source ON timeseries.economic_observations(source_id);

-- ----------------------------------------------------------------------------
-- Table: ingestion_log
-- ----------------------------------------------------------------------------
CREATE TABLE metadata.ingestion_log (
    log_id              SERIAL PRIMARY KEY,
    source_id           INTEGER NOT NULL REFERENCES metadata.data_sources(source_id),
    ingestion_start     TIMESTAMPTZ NOT NULL,
    ingestion_end       TIMESTAMPTZ,
    status              VARCHAR(20) NOT NULL,
    series_count        INTEGER,
    records_inserted    INTEGER,
    records_updated     INTEGER,
    date_range_start    DATE,
    date_range_end      DATE,
    error_message       TEXT,
    execution_metadata  JSONB,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_ingestion_source_date ON metadata.ingestion_log(source_id, created_at DESC);
CREATE INDEX idx_ingestion_status ON metadata.ingestion_log(status);

-- ============================================================================
-- SEED DATA
-- ============================================================================

INSERT INTO metadata.data_sources (source_name, api_type, base_url, requires_auth, rate_limit_rpm, notes) VALUES
('FRED', 'rest', 'https://api.stlouisfed.org/fred', TRUE, 120, 'Federal Reserve Economic Data - requires free API key'),
('ECB_SDW', 'sdmx', 'https://data-api.ecb.europa.eu/service', FALSE, 60, 'European Central Bank Statistical Data Warehouse'),
('BOE', 'rest', 'https://www.bankofengland.co.uk/boeapps/database', FALSE, NULL, 'Bank of England Statistical Interactive Database'),
('VALET', 'rest', 'https://www.bankofcanada.ca/valet', FALSE, NULL, 'Bank of Canada Valet API'),
('OECD', 'sdmx', 'https://stats.oecd.org/restsdmx/sdmx.ashx', FALSE, NULL, 'OECD Statistics API'),
('IMF', 'rest', 'http://dataservices.imf.org/REST/SDMX_JSON.svc', FALSE, NULL, 'IMF Data Services'),
('WORLD_BANK', 'rest', 'https://api.worldbank.org/v2', FALSE, NULL, 'World Bank Open Data API'),
('EUROSTAT', 'rest', 'https://ec.europa.eu/eurostat/api/dissemination', FALSE, NULL, 'Eurostat API')
ON CONFLICT (source_name) DO NOTHING;

-- ============================================================================
-- HELPER VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW timeseries.latest_observations AS
SELECT DISTINCT ON (series_id)
    series_id,
    observation_date,
    value,
    value_status
FROM timeseries.economic_observations
ORDER BY series_id, observation_date DESC;

CREATE OR REPLACE VIEW metadata.series_summary AS
SELECT
    sm.series_id,
    ds.source_name,
    sm.source_series_id,
    sm.series_name,
    sm.frequency,
    sm.units,
    sm.geography,
    sm.is_active,
    COUNT(eo.observation_date) AS observation_count,
    MIN(eo.observation_date) AS earliest_date,
    MAX(eo.observation_date) AS latest_date
FROM metadata.series_metadata sm
LEFT JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
LEFT JOIN timeseries.economic_observations eo ON sm.series_id = eo.series_id
GROUP BY sm.series_id, ds.source_name, sm.source_series_id, sm.series_name, 
         sm.frequency, sm.units, sm.geography, sm.is_active;