#!/bin/bash
# Test all installed extensions

echo "Testing PostgreSQL Extensions..."

psql -h chronos-db -U prometheus -d chronos_db << 'SQL'
\echo '===== Testing fuzzystrmatch ====='
SELECT
  'Levenshtein:' AS test,
  levenshtein('inflation', 'inflationn') AS result;

\echo '===== Testing pg_trgm ====='
SELECT
  'Similarity:' AS test,
  similarity('postgresql', 'postgres') AS result;

\echo '===== Testing PostGIS ====='
SELECT
  'Point:' AS test,
  ST_AsText(ST_GeomFromText('POINT(-79.3832 43.6532)')) AS result;

\echo '===== Testing pgvector ====='
SELECT
  'Vector Distance:' AS test,
  '[1,2,3]'::vector <-> '[4,5,6]'::vector AS result;

\echo '===== Testing Apache AGE ====='
SELECT * FROM cypher('economic_graph', $$
  MATCH (n)
  RETURN count(n) AS node_count
$$) AS (count agtype);

\echo '===== All Tests Complete ====='
SQL
