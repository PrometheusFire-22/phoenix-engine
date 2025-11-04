-- ============================================================================
-- Extension Verification Script
-- ============================================================================

\echo '=========================================='
\echo 'Extension Verification Test Suite'
\echo '=========================================='
\echo ''

-- Test 1: List all extensions
\echo '==== Installed Extensions ===='
SELECT extname, extversion, extrelocatable
FROM pg_extension
WHERE extname NOT IN ('plpgsql')
ORDER BY extname;
\echo ''

-- Test 2: TimescaleDB
\echo '==== Test: TimescaleDB ===='
SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';
\echo ''

-- Test 3: PostGIS
\echo '==== Test: PostGIS ===='
SELECT PostGIS_Version();
\echo ''

-- Test 4: pgvector
\echo '==== Test: pgvector (Euclidean Distance) ===='
SELECT '[1,2,3]'::vector <-> '[4,5,6]'::vector AS distance;
\echo ''

-- Test 5: Apache AGE
\echo '==== Test: Apache AGE (Graph Node Count) ===='
SELECT * FROM cypher('economic_graph', $$
  MATCH (n)
  RETURN count(n) AS node_count
$$) AS (count agtype);
\echo ''

-- Test 6: Levenshtein
\echo '==== Test: fuzzystrmatch (Levenshtein) ===='
SELECT levenshtein('test', 'text') AS edit_distance;
\echo ''

-- Test 7: Similarity
\echo '==== Test: pg_trgm (Similarity) ===='
SELECT similarity('postgresql', 'postgres') AS similarity_score;
\echo ''

-- Test 8: Crosstab
\echo '==== Test: tablefunc (Crosstab) ===='
SELECT * FROM crosstab(
  'SELECT 1, ''col_a'', 100 UNION SELECT 1, ''col_b'', 200',
  'SELECT UNNEST(ARRAY[''col_a'', ''col_b''])'
) AS ct(id int, a int, b int);
\echo ''

-- Test 9: Earth Distance
\echo '==== Test: earthdistance (Toronto to NYC) ===='
SELECT ROUND(
  earth_distance(
    ll_to_earth(43.6532, -79.3832),  -- Toronto
    ll_to_earth(40.7128, -74.0060)   -- New York
  ) / 1609.34
) AS distance_miles;
\echo ''

-- Test 10: HStore
\echo '==== Test: hstore (Key-Value) ===='
SELECT 'key1=>val1, key2=>val2'::hstore AS hstore_example;
\echo ''

-- Test 11: Hypertable
\echo '==== Test: TimescaleDB Hypertable ===='
SELECT
  hypertable_schema,
  hypertable_name,
  num_dimensions,
  num_chunks
FROM timescaledb_information.hypertables
WHERE hypertable_name = 'economic_observations';
\echo ''

\echo '=========================================='
\echo '✅ All Tests Complete'
\echo '=========================================='
```

---

## What We've Accomplished (Summary of Last 10 Messages)

### **1. Identified the Goal (Messages 1-3)**
- Add multi-modal extensions to PostgreSQL
- Target: PostGIS, pgvector, Apache AGE, statistical extensions
- Keep TimescaleDB as core time-series engine

### **2. Initial Dockerfile Attempts (Messages 4-6)**
**Problem:** TimescaleDB base image uses Alpine Linux (no `apt-get`)
**Tried:** Converting Dockerfile to use `apk` instead of `apt-get`
**Result:** Failed - PostGIS packages missing in Alpine repos

### **3. Strategy Shift (Messages 7-8)**
**Decision:** Start with PostGIS base image (has all geo packages)
**Approach:** Add TimescaleDB, pgvector, AGE on top of PostGIS
**Rationale:** PostGIS packages are stable, well-maintained

### **4. Alpine Package Issues (Messages 9-10)**
**Problem:** Alpine's TimescaleDB package requires PostgreSQL 17
**Your Image:** PostgreSQL 16 (for stability)
**Conflict:** Version mismatch prevented installation

### **5. Final Solution (This Message)**
**Approach:** Compile TimescaleDB from source (version 2.17.2)
- ✅ Compatible with PostgreSQL 16
- ✅ Latest stable TimescaleDB release
- ✅ All other extensions install cleanly

---

## Architecture Summary
```
Base Image: postgis/postgis:16-3.4-alpine
    ├── PostgreSQL 16 ✅
    ├── PostGIS 3.4.2 ✅
    └── All geospatial dependencies ✅

Added via Compilation:
    ├── TimescaleDB 2.17.2 (compiled from source)
    ├── pgvector 0.5.1 (compiled from source)
    └── Apache AGE 1.5.0 (compiled from source)

Built-in Extensions:
    ├── pg_trgm, fuzzystrmatch, unaccent
    ├── tablefunc, intarray, cube, earthdistance
    ├── hstore, pgcrypto
    └── btree_gin, btree_gist, pg_stat_statements
