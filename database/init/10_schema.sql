CREATE SCHEMA IF NOT EXISTS metadata;
CREATE SCHEMA IF NOT EXISTS timeseries;
CREATE SCHEMA IF NOT EXISTS analytics;

CREATE TABLE metadata.data_sources (
    source_id SERIAL PRIMARY KEY,
    source_name VARCHAR(100) NOT NULL UNIQUE,
    source_description TEXT,
    base_url VARCHAR(500)
);
CREATE TABLE metadata.series_metadata (
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
    is_active BOOLEAN DEFAULT TRUE, -- THIS IS THE FIX
    observation_count INTEGER DEFAULT 0,
    UNIQUE(source_id, source_series_id)
);
CREATE TABLE metadata.ingestion_log (
    log_id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES metadata.data_sources(source_id),
    ingestion_start TIMESTAMPTZ NOT NULL,
    ingestion_end TIMESTAMPTZ,
    status VARCHAR(20) CHECK (status IN ('running', 'success', 'failed')),
    series_count INTEGER,
    records_inserted INTEGER,
    error_message TEXT
);
CREATE TABLE timeseries.economic_observations (
    series_id INTEGER NOT NULL,
    observation_date DATE NOT NULL,
    value NUMERIC(20, 6),
    PRIMARY KEY (series_id, observation_date)
);
CREATE TABLE metadata.schema_version (version VARCHAR(20) PRIMARY KEY, applied_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP);
