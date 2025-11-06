-- Seed the data_sources table
INSERT INTO metadata.data_sources (source_name, source_description, base_url)
VALUES
    ('FRED', 'Federal Reserve Economic Data', 'https://api.stlouisfed.org/fred'),
    ('VALET', 'Bank of Canada Valet API', 'https://www.bankofcanada.ca/valet')
ON CONFLICT (source_name) DO NOTHING;
