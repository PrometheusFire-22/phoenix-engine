-- ============================================================================
-- Migration: Add PostgreSQL Extensions for Multi-Modal Analytics
-- Version: 002
-- Date: 2024-11-03
-- Author: prometheus
-- Purpose: Enable geospatial, vector, statistical, and graph capabilities
-- ============================================================================

-- Performance & Statistics
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Text Search
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Geospatial
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Vector Embeddings
CREATE EXTENSION IF NOT EXISTS vector;

-- Statistical Analysis
CREATE EXTENSION IF NOT EXISTS tablefunc;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS hstore;

-- Graph Database
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;
SELECT create_graph('economic_graph');

-- ============================================================================
-- Verification
-- ============================================================================

-- List all installed extensions
DO $$
DECLARE
    ext_record RECORD;
BEGIN
    RAISE NOTICE 'Installed Extensions:';
    FOR ext_record IN
        SELECT extname, extversion
        FROM pg_extension
        WHERE extname NOT IN ('plpgsql')
        ORDER BY extname
    LOOP
        RAISE NOTICE '  - %: v%', ext_record.extname, ext_record.extversion;
    END LOOP;
END $$;
SQL
