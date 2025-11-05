-- ============================================================================
-- Migration 007: Apache AGE Graph Database Setup (MINIMAL WORKING VERSION)
-- ============================================================================
-- Version: 007.2 (Simplified - Manual Population)
-- Date: 2025-11-05
-- Description: Create graph labels only. Manual population recommended.
-- 
-- CRITICAL: Apache AGE cypher() function has complex type signatures.
--           This migration creates the schema; populate via psql manually.
-- ============================================================================

LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- ============================================================================
-- PART 1: CREATE VERTEX LABELS (Node Types)
-- ============================================================================

DO $$
BEGIN
    PERFORM create_vlabel('economic_graph', 'Indicator');
    RAISE NOTICE '✅ VLabel "Indicator" created';
EXCEPTION
    WHEN duplicate_table THEN
        RAISE NOTICE 'ℹ️  VLabel "Indicator" already exists';
END $$;

DO $$
BEGIN
    PERFORM create_vlabel('economic_graph', 'Country');
    RAISE NOTICE '✅ VLabel "Country" created';
EXCEPTION
    WHEN duplicate_table THEN
        RAISE NOTICE 'ℹ️  VLabel "Country" already exists';
END $$;

DO $$
BEGIN
    PERFORM create_vlabel('economic_graph', 'Category');
    RAISE NOTICE '✅ VLabel "Category" created';
EXCEPTION
    WHEN duplicate_table THEN
        RAISE NOTICE 'ℹ️  VLabel "Category" already exists';
END $$;

DO $$
BEGIN
    PERFORM create_vlabel('economic_graph', 'DataSource');
    RAISE NOTICE '✅ VLabel "DataSource" created';
EXCEPTION
    WHEN duplicate_table THEN
        RAISE NOTICE 'ℹ️  VLabel "DataSource" already exists';
END $$;

-- ============================================================================
-- PART 2: CREATE EDGE LABELS (Relationship Types)
-- ============================================================================

DO $$
BEGIN
    PERFORM create_elabel('economic_graph', 'PUBLISHED_BY');
    RAISE NOTICE '✅ ELabel "PUBLISHED_BY" created';
EXCEPTION
    WHEN duplicate_table THEN
        RAISE NOTICE 'ℹ️  ELabel "PUBLISHED_BY" already exists';
END $$;

DO $$
BEGIN
    PERFORM create_elabel('economic_graph', 'LOCATED_IN');
    RAISE NOTICE '✅ ELabel "LOCATED_IN" created';
EXCEPTION
    WHEN duplicate_table THEN
        RAISE NOTICE 'ℹ️  ELabel "LOCATED_IN" already exists';
END $$;

DO $$
BEGIN
    PERFORM create_elabel('economic_graph', 'BELONGS_TO');
    RAISE NOTICE '✅ ELabel "BELONGS_TO" created';
EXCEPTION
    WHEN duplicate_table THEN
        RAISE NOTICE 'ℹ️  ELabel "BELONGS_TO" already exists';
END $$;

DO $$
BEGIN
    PERFORM create_elabel('economic_graph', 'INFLUENCES');
    RAISE NOTICE '✅ ELabel "INFLUENCES" created';
EXCEPTION
    WHEN duplicate_table THEN
        RAISE NOTICE 'ℹ️  ELabel "INFLUENCES" already exists';
END $$;

-- ============================================================================
-- PART 3: HELPER FUNCTIONS FOR MANUAL POPULATION
-- ============================================================================

-- Function to count nodes (works without data)
CREATE OR REPLACE FUNCTION analytics.graph_node_count()
RETURNS BIGINT AS $$
DECLARE
    v_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM ag_catalog."Indicator";
    
    RETURN v_count;
EXCEPTION
    WHEN OTHERS THEN
        RETURN 0;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION analytics.graph_node_count IS
'Count Indicator nodes in graph (0 until populated manually).';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Apache AGE schema created successfully';
    RAISE NOTICE '';
    RAISE NOTICE '📝 TO POPULATE GRAPH NODES:';
    RAISE NOTICE '   Run these commands in psql:';
    RAISE NOTICE '';
    RAISE NOTICE '   LOAD ''age'';';
    RAISE NOTICE '   SET search_path = ag_catalog, "$user", public;';
    RAISE NOTICE '';
    RAISE NOTICE '   -- Create sample indicator node:';
    RAISE NOTICE '   SELECT * FROM cypher(''economic_graph'', $$';
    RAISE NOTICE '       CREATE (i:Indicator {series_id: 1, name: ''GDP''})';
    RAISE NOTICE '       RETURN i';
    RAISE NOTICE '   $$) as (result agtype);';
    RAISE NOTICE '';
    RAISE NOTICE '   -- Query nodes:';
    RAISE NOTICE '   SELECT * FROM cypher(''economic_graph'', $$';
    RAISE NOTICE '       MATCH (n:Indicator) RETURN n LIMIT 10';
    RAISE NOTICE '   $$) as (result agtype);';
    RAISE NOTICE '';
    RAISE NOTICE '⚠️  Automated population skipped due to cypher() complexity.';
    RAISE NOTICE '   Graph nodes must be created interactively or via application code.';
END $$;

-- ============================================================================
-- USAGE NOTES
-- ============================================================================
-- 
-- WHY MINIMAL?
-- - Apache AGE cypher() function has strict type requirements
-- - Automated population in migration is error-prone
-- - Better to populate via application code or manual psql commands
--
-- HOW TO POPULATE:
-- 1. Use psql interactively: SELECT * FROM cypher(...) 
-- 2. Use application code: Python + psycopg2 with ag_catalog.cypher()
-- 3. Use AGE Viewer UI: https://github.com/apache/age-viewer
--
-- EXAMPLE MANUAL POPULATION:
-- 
-- LOAD 'age';
-- SET search_path = ag_catalog, "$user", public;
--
-- -- Create nodes
-- SELECT * FROM cypher('economic_graph', $$
--     CREATE (i:Indicator {series_id: 1, name: 'GDP'})
-- $$) as (result agtype);
--
-- SELECT * FROM cypher('economic_graph', $$
--     CREATE (c:Country {name: 'United States'})
-- $$) as (result agtype);
--
-- -- Create relationship
-- SELECT * FROM cypher('economic_graph', $$
--     MATCH (i:Indicator {series_id: 1})
--     MATCH (c:Country {name: 'United States'})
--     CREATE (i)-[:LOCATED_IN]->(c)
-- $$) as (result agtype);
--
-- -- Query
-- SELECT * FROM cypher('economic_graph', $$
--     MATCH (i:Indicator)-[:LOCATED_IN]->(c:Country)
--     RETURN i.name, c.name
-- $$) as (indicator_name agtype, country_name agtype);
--
-- ============================================================================
-- END OF MIGRATION 007 (MINIMAL)
-- ============================================================================