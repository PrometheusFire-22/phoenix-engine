INSERT INTO metadata.schema_version (version) VALUES ('3.0.0') ON CONFLICT (version) DO NOTHING;
