#!/bin/bash
# ============================================================================
# Project Chronos: PostgreSQL Extension Installer
# Purpose: Install and verify all required extensions
# ============================================================================

set -e

echo "=================================================="
echo "Installing PostgreSQL Extensions"
echo "=================================================="

# Wait for PostgreSQL to be ready
until pg_isready -U postgres; do
    echo "Waiting for PostgreSQL..."
    sleep 2
done

# Install all extensions
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- ========================================================================
    -- Core Extensions (Always Available)
    -- ========================================================================
    CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    CREATE EXTENSION IF NOT EXISTS btree_gin;
    CREATE EXTENSION IF NOT EXISTS btree_gist;
    CREATE EXTENSION IF NOT EXISTS hstore;
    CREATE EXTENSION IF NOT EXISTS pgcrypto;

    -- ========================================================================
    -- Text & Fuzzy Matching
    -- ========================================================================
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE EXTENSION IF NOT EXISTS unaccent;
    CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

    -- ========================================================================
    -- Statistical & Analytical
    -- ========================================================================
    CREATE EXTENSION IF NOT EXISTS tablefunc;
    CREATE EXTENSION IF NOT EXISTS intarray;
    CREATE EXTENSION IF NOT EXISTS cube;
    CREATE EXTENSION IF NOT EXISTS earthdistance;

    -- ========================================================================
    -- Geospatial (PostGIS)
    -- ========================================================================
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS postgis_topology;
    CREATE EXTENSION IF NOT EXISTS postgis_raster;

    -- ========================================================================
    -- Vector Embeddings
    -- ========================================================================
    CREATE EXTENSION IF NOT EXISTS vector;

    -- ========================================================================
    -- Graph Database (Apache AGE)
    -- ========================================================================
    CREATE EXTENSION IF NOT EXISTS age CASCADE;
    LOAD 'age';
    SET search_path = ag_catalog, "\$user", public;

    -- Create default economic graph
    SELECT ag_catalog.create_graph('economic_graph');

    -- ========================================================================
    -- Verification
    -- ========================================================================
    DO \$\$
    DECLARE
        ext_record RECORD;
    BEGIN
        RAISE NOTICE '';
        RAISE NOTICE '==============================================';
        RAISE NOTICE 'Installed Extensions:';
        RAISE NOTICE '==============================================';
        FOR ext_record IN
            SELECT extname, extversion
            FROM pg_extension
            WHERE extname NOT IN ('plpgsql')
            ORDER BY extname
        LOOP
            RAISE NOTICE '  ✅ %-25s v%', ext_record.extname, ext_record.extversion;
        END LOOP;
        RAISE NOTICE '==============================================';
    END \$\$;
EOSQL

echo "✅ All extensions installed and verified"
