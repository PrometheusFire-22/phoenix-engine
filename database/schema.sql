-- ============================================================================
-- Project Chronos: Complete Database Schema
-- Version: 2.0.0 (Multi-Modal Extensions)
-- Last Updated: 2024-11-03
-- ============================================================================
--
-- This file is the SINGLE SOURCE OF TRUTH for the database structure.
-- All extensions, schemas, tables, views, and functions are documented here.
--
-- ============================================================================

-- ============================================================================
-- POSTGRESQL EXTENSIONS
-- ============================================================================
-- Purpose: Enable multi-modal data capabilities
-- Categories: Time-series, Geospatial, Vector Search, Graph Database, Text Processing

-- ----------------------------------------------------------------------------
-- Time-Series Database (Core)
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
COMMENT ON EXTENSION timescaledb IS
'TimescaleDB: Scalable time-series database built on PostgreSQL';

-- ----------------------------------------------------------------------------
-- Performance & Monitoring
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
COMMENT ON EXTENSION pg_stat_statements IS
'Track planning and execution statistics of all SQL statements executed';

CREATE EXTENSION IF NOT EXISTS btree_gin;
COMMENT ON EXTENSION btree_gin IS
'Support for indexing common datatypes in GIN (Generalized Inverted Index)';

CREATE EXTENSION IF NOT EXISTS btree_gist;
COMMENT ON EXTENSION btree_gist IS
'Support for indexing common datatypes in GiST (Generalized Search Tree)';

-- ----------------------------------------------------------------------------
-- Text Processing & Fuzzy Matching
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;
COMMENT ON EXTENSION pg_trgm IS
'Trigram matching for similarity searches and fuzzy string matching';

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
COMMENT ON EXTENSION fuzzystrmatch IS
'Levenshtein distance, Soundex, and Metaphone for fuzzy text matching';

CREATE EXTENSION IF NOT EXISTS unaccent;
COMMENT ON EXTENSION unaccent IS
'Text search dictionary that removes accents (diacritics) from lexemes';

-- ----------------------------------------------------------------------------
-- Statistical & Analytical Functions
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS tablefunc;
COMMENT ON EXTENSION tablefunc IS
'Functions for crosstab (pivot tables), connectby, and other table manipulations';

CREATE EXTENSION IF NOT EXISTS intarray;
COMMENT ON EXTENSION intarray IS
'Functions and operators for manipulating integer arrays';

CREATE EXTENSION IF NOT EXISTS cube;
COMMENT ON EXTENSION cube IS
'Data type for multidimensional cubes for OLAP operations';

CREATE EXTENSION IF NOT EXISTS earthdistance CASCADE;
COMMENT ON EXTENSION earthdistance IS
'Calculate great circle distances on the surface of the Earth';

-- ----------------------------------------------------------------------------
-- Key-Value & Flexible Schema
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS hstore;
COMMENT ON EXTENSION hstore IS
'Data type for storing sets of (key, value) pairs within a single PostgreSQL value';

CREATE EXTENSION IF NOT EXISTS pgcrypto;
COMMENT ON EXTENSION pgcrypto IS
'Cryptographic functions including hashing, encryption, and random data generation';

-- ----------------------------------------------------------------------------
-- Geospatial Analysis (PostGIS)
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS postgis CASCADE;
COMMENT ON EXTENSION postgis IS
'PostGIS geometry, geography, and raster spatial types and functions';

CREATE EXTENSION IF NOT EXISTS postgis_topology;
COMMENT ON EXTENSION postgis_topology IS
'PostGIS topology spatial types and functions for advanced spatial relationships';

CREATE EXTENSION IF NOT EXISTS postgis_raster;
COMMENT ON EXTENSION postgis_raster IS
'PostGIS raster types and functions for working with raster data';

-- ----------------------------------------------------------------------------
-- Vector Embeddings & Semantic Search
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS vector;
COMMENT ON EXTENSION vector IS
'pgvector: Open-source vector similarity search with ivfflat and hnsw indexes';

-- ----------------------------------------------------------------------------
-- Graph Database (Apache AGE)
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS age CASCADE;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;
COMMENT ON EXTENSION age IS
'Apache AGE: Graph database extension providing Cypher query language (openCypher)';

-- Create default graph for economic relationships
SELECT ag_catalog.create_graph('economic_graph');

COMMENT ON SCHEMA ag_catalog IS
'Apache AGE catalog schema containing graph database infrastructure';

-- ============================================================================
-- SCHEMAS
-- ============================================================================

-- Metadata: Series definitions, data sources, ingestion logs
CREATE SCHEMA IF NOT EXISTS metadata;
COMMENT ON SCHEMA metadata IS
'Series metadata, data source configuration, and ingestion tracking';

-- Time-series: Economic observations (TimescaleDB hypertable)
CREATE SCHEMA IF NOT EXISTS timeseries;
COMMENT ON SCHEMA timeseries IS
'Time-series data stored in TimescaleDB hypertables for optimized querying';

-- Analytics: Materialized views and derived metrics
CREATE SCHEMA IF NOT EXISTS analytics;
COMMENT ON SCHEMA analytics IS
'Pre-computed analytics views for common queries and dashboards';

-- ============================================================================
-- METADATA TABLES
-- ============================================================================

-- Data sources (FRED, Bank of Canada, etc.)
CREATE TABLE IF NOT EXISTS metadata.data_sources (
    source_id SERIAL PRIMARY KEY,
    source_name VARCHAR(100) NOT NULL UNIQUE,
    source_description TEXT,
    base_url VARCHAR(500),
    api_key_required BOOLEAN DEFAULT TRUE,
    rate_limit_per_minute INTEGER,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE metadata.data_sources IS
'External data source configuration and API details';

-- Series metadata
CREATE TABLE IF NOT EXISTS metadata.series_metadata (
    series_id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES metadata.data_sources(source_id),
    source_series_id VARCHAR(100) NOT NULL,
    series_name VARCHAR(255) NOT NULL,
    series_description TEXT,
    series_type VARCHAR(50),
    frequency VARCHAR(20),
    units VARCHAR(100),
    seasonal_adjustment VARCHAR(50),
    last_updated TIMESTAMPTZ,
    geography VARCHAR(100),
    category VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,  -- ADD THIS LINE
    description_embedding vector(384),
    location geography(POINT, 4326),
    metadata_json hstore,
    UNIQUE(source_id, source_series_id)
);

COMMENT ON TABLE metadata.series_metadata IS
'Economic indicator definitions with multi-modal capabilities';

COMMENT ON COLUMN metadata.series_metadata.description_embedding IS
'384-dimensional vector embedding of series description (sentence-transformers/all-MiniLM-L6-v2)';

COMMENT ON COLUMN metadata.series_metadata.location IS
'Geographic point (lat/lon) for regional series using PostGIS geography type';

COMMENT ON COLUMN metadata.series_metadata.metadata_json IS
'Flexible key-value pairs for source-specific metadata using hstore';

-- Ingestion logs
CREATE TABLE IF NOT EXISTS metadata.ingestion_log (
    log_id SERIAL PRIMARY KEY,
    source_id INTEGER REFERENCES metadata.data_sources(source_id),
    series_id INTEGER REFERENCES metadata.series_metadata(series_id),
    ingestion_start TIMESTAMPTZ NOT NULL,
    ingestion_end TIMESTAMPTZ,
    records_fetched INTEGER,
    records_inserted INTEGER,
    records_updated INTEGER,
    status VARCHAR(20) CHECK (status IN ('running', 'success', 'failed', 'partial')),
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE metadata.ingestion_log IS
'Audit trail of data ingestion jobs with success/failure tracking';

-- ============================================================================
-- TIME-SERIES TABLES (TimescaleDB Hypertables)
-- ============================================================================

CREATE TABLE IF NOT EXISTS timeseries.economic_observations (
    series_id INTEGER NOT NULL REFERENCES metadata.series_metadata(series_id),
    observation_date DATE NOT NULL,
    value NUMERIC(20, 6),
    quality_flag VARCHAR(10),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (series_id, observation_date)
);

COMMENT ON TABLE timeseries.economic_observations IS
'Time-series observations stored as TimescaleDB hypertable (partitioned by observation_date)';

-- Convert to hypertable (1-year chunks)
SELECT create_hypertable(
    'timeseries.economic_observations',
    'observation_date',
    chunk_time_interval => INTERVAL '1 year',
    if_not_exists => TRUE
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Series metadata indexes
CREATE INDEX IF NOT EXISTS idx_series_source
ON metadata.series_metadata(source_id);

CREATE INDEX IF NOT EXISTS idx_series_name_trgm
ON metadata.series_metadata USING gin(series_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_series_description_trgm
ON metadata.series_metadata USING gin(series_description gin_trgm_ops);

-- Vector similarity index (for semantic search)
CREATE INDEX IF NOT EXISTS idx_series_embedding
ON metadata.series_metadata
USING ivfflat (description_embedding vector_cosine_ops)
WITH (lists = 100);

-- Geospatial index (for location queries)
CREATE INDEX IF NOT EXISTS idx_series_location
ON metadata.series_metadata
USING gist(location);

-- Observations indexes
CREATE INDEX IF NOT EXISTS idx_obs_date
ON timeseries.economic_observations(observation_date DESC);

CREATE INDEX IF NOT EXISTS idx_obs_value
ON timeseries.economic_observations(value)
WHERE value IS NOT NULL;

-- ============================================================================
-- ANALYTICS VIEWS
-- ============================================================================

-- FX rates normalized to USD base
CREATE OR REPLACE VIEW analytics.fx_rates_normalized AS
SELECT
    sm.series_name,
    eo.observation_date,
    eo.value as original_rate,
    CASE
        WHEN sm.series_name LIKE '%USD%' THEN eo.value
        WHEN sm.series_name LIKE 'FX%CAD' THEN 1.0 / eo.value
        ELSE eo.value
    END as usd_rate,
    sm.source_series_id
FROM timeseries.economic_observations eo
JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
WHERE sm.series_type = 'FX'
  AND eo.value IS NOT NULL;

COMMENT ON VIEW analytics.fx_rates_normalized IS
'Foreign exchange rates normalized to USD base for consistent cross-currency calculations';

-- Latest macro indicators with YoY growth
CREATE OR REPLACE VIEW analytics.macro_indicators_latest AS
WITH latest_values AS (
    SELECT DISTINCT ON (series_id)
        series_id,
        observation_date,
        value
    FROM timeseries.economic_observations
    WHERE value IS NOT NULL
    ORDER BY series_id, observation_date DESC
),
year_ago_values AS (
    SELECT
        lv.series_id,
        eo.value as value_year_ago
    FROM latest_values lv
    LEFT JOIN timeseries.economic_observations eo
        ON lv.series_id = eo.series_id
        AND eo.observation_date = lv.observation_date - INTERVAL '1 year'
)
SELECT
    sm.series_name,
    sm.source_series_id,
    lv.observation_date,
    lv.value as current_value,
    yav.value_year_ago,
    CASE
        WHEN yav.value_year_ago IS NOT NULL AND yav.value_year_ago != 0
        THEN ((lv.value - yav.value_year_ago) / yav.value_year_ago * 100)
        ELSE NULL
    END as yoy_growth_pct
FROM latest_values lv
JOIN metadata.series_metadata sm ON lv.series_id = sm.series_id
LEFT JOIN year_ago_values yav ON lv.series_id = yav.series_id
ORDER BY sm.series_name;

COMMENT ON VIEW analytics.macro_indicators_latest IS
'Most recent values for all indicators with year-over-year growth calculations';

-- Data quality dashboard
CREATE OR REPLACE VIEW analytics.data_quality_dashboard AS
SELECT
    sm.series_name,
    sm.source_series_id,
    COUNT(eo.value) as total_observations,
    MIN(eo.observation_date) as first_observation,
    MAX(eo.observation_date) as last_observation,
    CURRENT_DATE - MAX(eo.observation_date) as days_since_update,
    CASE
        WHEN CURRENT_DATE - MAX(eo.observation_date) <= 7 THEN 'fresh'
        WHEN CURRENT_DATE - MAX(eo.observation_date) <= 30 THEN 'recent'
        WHEN CURRENT_DATE - MAX(eo.observation_date) <= 90 THEN 'stale'
        ELSE 'very_stale'
    END as freshness_status,
    ROUND(
        100.0 * COUNT(CASE WHEN eo.value IS NULL THEN 1 END) / COUNT(*),
        2
    ) as null_percentage
FROM metadata.series_metadata sm
LEFT JOIN timeseries.economic_observations eo ON sm.series_id = eo.series_id
GROUP BY sm.series_id, sm.series_name, sm.source_series_id
ORDER BY days_since_update;

COMMENT ON VIEW analytics.data_quality_dashboard IS
'Data freshness, completeness, and quality metrics for monitoring';

-- ============================================================================
-- GRAPH SCHEMA (Apache AGE)
-- ============================================================================
-- Note: Graph schema is managed through Apache AGE Cypher queries
-- Default graph 'economic_graph' created above
--
-- Node Labels:
--   - Indicator: Economic indicators (GDP, CPI, etc.)
--   - Country: Geographic entities
--   - Sector: Economic sectors
--   - DataSource: Origin of data
--
-- Relationship Types:
--   - INFLUENCES: Causal relationships (e.g., interest rate → mortgage rate)
--   - CORRELATES_WITH: Statistical correlation
--   - LEADS: Leading indicator relationships
--   - PUBLISHED_BY: Data source relationships
--   - MEASURES: Indicator → Sector relationships

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to tables
CREATE TRIGGER update_series_metadata_updated_at
    BEFORE UPDATE ON metadata.series_metadata
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_observations_updated_at
    BEFORE UPDATE ON timeseries.economic_observations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Insert data sources
INSERT INTO metadata.data_sources (source_name, source_description, base_url, api_key_required, rate_limit_per_minute)
VALUES
    ('FRED', 'Federal Reserve Economic Data', 'https://api.stlouisfed.org/fred', TRUE, 120),
    ('Bank of Canada Valet', 'Bank of Canada Valet API', 'https://www.bankofcanada.ca/valet', FALSE, 60)
ON CONFLICT (source_name) DO NOTHING;

-- ============================================================================
-- PERMISSIONS (Production security - customize as needed)
-- ============================================================================

-- Grant read-only to analytics role (if needed)
-- GRANT SELECT ON ALL TABLES IN SCHEMA metadata TO analytics_reader;
-- GRANT SELECT ON ALL TABLES IN SCHEMA timeseries TO analytics_reader;
-- GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO analytics_reader;

-- ============================================================================
-- SCHEMA VERSION INFO
-- ============================================================================

CREATE TABLE IF NOT EXISTS metadata.schema_version (
    version VARCHAR(20) PRIMARY KEY,
    applied_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    description TEXT
);

INSERT INTO metadata.schema_version (version, description)
VALUES ('2.0.0', 'Multi-modal extensions: PostGIS, pgvector, Apache AGE, statistical functions')
ON CONFLICT (version) DO NOTHING;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
