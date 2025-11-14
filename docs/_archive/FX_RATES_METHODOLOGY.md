# Foreign Exchange Rate Normalization Methodology

## Overview

All FX rates in the `analytics.fx_rates_normalized` view are expressed as **USD per 1 unit of foreign currency**.

## Data Sources and Transformations

### Type 1: Native USD Rates (No Transformation)

**Sources:** FRED DEXUSEU, DEXUSUK, DEXUSAL, DEXUSNZ

These series are already published as USD per FX.

**Example:**
- DEXUSEU = 1.0800 means 1 EUR = 1.08 USD ✅ No change needed

---

### Type 2: Inverted Rates (Simple Inversion)

**Sources:** FRED DEXCAUS, DEXJPUS; Bank of Canada FXUSDCAD

These series are published as FX per USD. We invert to get USD per FX.

**Formula:** `usd_per_fx = 1 / raw_value`

**Example:**
- DEXCAUS raw = 1.3500 (CAD per USD)
- Normalized = 1 / 1.3500 = 0.7407 (USD per CAD) ✅

---

### Type 3: Cross-Rate Calculation (CAD-Based Conversion)

**Sources:** Bank of Canada FXEURCAD, FXGBPCAD, FXJPYCAD, etc.

These series are published as CAD per FX. To get USD per FX, we multiply by the USD/CAD rate.

**Formula:** `usd_per_fx = (CAD per FX) × (USD per CAD)`

**Example:**
```
FXEURCAD raw = 1.627 (CAD per EUR)
FXUSDCAD raw = 1.396 (CAD per USD) → inverted = 0.7164 (USD per CAD)

USD per EUR = 1.627 × 0.7164 = 1.1656 ✅
```

**Why This Works:**
```
CAD/EUR × USD/CAD = USD/EUR
```

The CAD units cancel out, leaving USD/EUR.

---

## Verification Against Market Data

You can verify our cross-rate calculations against direct market rates:
```sql
SELECT 
    observation_date,
    MAX(CASE WHEN source_series_id = 'DEXUSEU' THEN usd_per_fx END) as eur_usd_direct,
    MAX(CASE WHEN source_series_id = 'FXEURCAD' THEN usd_per_fx END) as eur_usd_via_cad,
    ABS(MAX(CASE WHEN source_series_id = 'DEXUSEU' THEN usd_per_fx END) - 
        MAX(CASE WHEN source_series_id = 'FXEURCAD' THEN usd_per_fx END)) as difference
FROM analytics.fx_rates_normalized
WHERE source_series_id IN ('DEXUSEU', 'FXEURCAD')
  AND observation_date >= '2024-10-01'
GROUP BY observation_date
ORDER BY observation_date DESC
LIMIT 10;
```

**Expected:** Small differences (~1-5%) due to:
- Bid/ask spreads
- Time-of-day differences in publication
- CAD market volatility

---

## Common Pitfalls (AVOIDED)

❌ **Wrong:** Simple inversion of CAD-based rates
```sql
-- This gives EUR per CAD, NOT USD per EUR!
1 / FXEURCAD = 1 / 1.627 = 0.6146
```

✅ **Correct:** Cross-rate calculation
```sql
-- This gives USD per EUR
FXEURCAD × (1 / FXUSDCAD) = 1.627 × 0.7164 = 1.1656
```

---

## Usage Examples

### Compare Same Currency from Different Sources
```sql
-- CAD rates from FRED vs Bank of Canada
SELECT 
    observation_date,
    source_series_id,
    usd_per_fx,
    rate_description
FROM analytics.fx_rates_normalized
WHERE source_series_id IN ('DEXCAUS', 'FXUSDCAD')
  AND observation_date >= '2024-10-01'
ORDER BY observation_date DESC, source_series_id
LIMIT 20;
```

### Track Currency Strength Over Time
```sql
-- USD strength vs basket of currencies
SELECT 
    observation_date,
    AVG(usd_per_fx) as avg_usd_per_fx,
    STDDEV(usd_per_fx) as volatility
FROM analytics.fx_rates_normalized
WHERE source_series_id IN ('FXEURCAD', 'FXGBPCAD', 'FXJPYCAD')
  AND observation_date >= '2024-01-01'
GROUP BY observation_date
ORDER BY observation_date;
```

---

## Technical Notes

- **Date Matching:** Cross-rate calculations require USD/CAD rate for same date
- **Missing Dates:** If USD/CAD missing for a date, cross-rate rows excluded (rare)
- **Transparency:** Column `usd_cad_rate_used` shows the conversion rate applied
- **Audit Trail:** Column `transformation_type` indicates method used
