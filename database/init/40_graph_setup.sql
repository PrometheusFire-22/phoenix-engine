CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- Create the graph if it doesn't exist (idempotent)
DO $$
BEGIN
    PERFORM ag_catalog.create_graph('economic_graph');
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE 'Graph "economic_graph" already exists, skipping';
END
$$;

DO $$ BEGIN PERFORM create_vlabel('economic_graph', 'Indicator'); EXCEPTION WHEN duplicate_table THEN RAISE NOTICE 'VLabel "Indicator" already exists'; END $$;
DO $$ BEGIN PERFORM create_vlabel('economic_graph', 'Country'); EXCEPTION WHEN duplicate_table THEN RAISE NOTICE 'VLabel "Country" already exists'; END $$;
DO $$ BEGIN PERFORM create_elabel('economic_graph', 'LOCATED_IN'); EXCEPTION WHEN duplicate_table THEN RAISE NOTICE 'ELabel "LOCATED_IN" already exists'; END $$;
