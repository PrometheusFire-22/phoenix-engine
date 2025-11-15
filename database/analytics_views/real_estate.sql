-- ==============================================================================
--  Real Estate Analytics Views
-- ==============================================================================
-- Version: 1.0
-- Purpose: Analytical views for the Real Estate vertical.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- VIEW: v_cook_county_housing_pilot
-- ------------------------------------------------------------------------------
-- This view serves as a pilot for the Housing Affordability Stress Map,
-- focusing on Cook County, IL. It joins local home price and income data
-- to calculate a time-series affordability ratio.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.v_cook_county_housing_pilot AS
WITH
    -- Step 1: Isolate the time-series for Cook County House Price Index
    home_price AS (
        SELECT
            observation_date,
            value AS price_index
        FROM timeseries.economic_observations
        WHERE series_id = (
            SELECT series_id FROM metadata.series_metadata
            -- ✅ CORRECTED LINE: Use the actual column name from the table
            WHERE source_series_id = 'ATNHPIUS17031A'
        )
    ),
    -- Step 2: Isolate the time-series for Cook County Median Income
    income AS (
        SELECT
            observation_date,
            value AS median_income
        FROM timeseries.economic_observations
        WHERE series_id = (
            SELECT series_id FROM metadata.series_metadata
            -- ✅ CORRECTED LINE: Use the actual column name from the table
            WHERE source_series_id = 'MHIIL17031A052NCEN'
        )
    )
-- Step 3: Join the two series on their date and calculate the ratio
SELECT
    hp.observation_date,
    hp.price_index,
    i.median_income,
    -- The core affordability ratio calculation. A higher number means less affordable.
    (hp.price_index / NULLIF(i.median_income, 0)) AS affordability_ratio
FROM
    home_price hp
-- Use a LEFT JOIN to ensure we keep all price data points, even if income data is sparse
LEFT JOIN
    income i ON hp.observation_date = i.observation_date
WHERE
    i.median_income IS NOT NULL -- Only include dates where we have both data points
ORDER BY
    hp.observation_date DESC;

COMMENT ON VIEW analytics.v_cook_county_housing_pilot IS 'Pilot view for housing affordability in Cook County, IL, calculating a ratio of house price index to median income.';
