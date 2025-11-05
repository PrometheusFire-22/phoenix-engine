-- ============================================================================
-- Project Chronos: Seed Data
-- Description: Populates the essential lookup tables with initial values.
-- ============================================================================

-- Insert the primary data sources for the ingestion scripts
-- ON CONFLICT: Prevents errors if the script is run on a database that
-- already contains this data.
INSERT INTO metadata.data_sources (source_name, source_url) VALUES
    ('FRED', 'https://fred.stlouisfed.org/'\),
    ('VALET', 'https://www.bankofcanada.ca/valet/'\)
ON CONFLICT (source_name) DO NOTHING;
