CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;
DO $$ BEGIN PERFORM create_vlabel('economic_graph', 'Indicator'); EXCEPTION WHEN duplicate_table THEN RAISE NOTICE 'VLabel "Indicator" already exists'; END $$;
DO $$ BEGIN PERFORM create_vlabel('economic_graph', 'Country'); EXCEPTION WHEN duplicate_table THEN RAISE NOTICE 'VLabel "Country" already exists'; END $$;
DO $$ BEGIN PERFORM create_elabel('economic_graph', 'LOCATED_IN'); EXCEPTION WHEN duplicate_table THEN RAISE NOTICE 'ELabel "LOCATED_IN" already exists'; END $$;
