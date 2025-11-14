# Data Quality Assurance Checklist

## Pre-Ingestion (Before Adding New Series)

- [ ] **Verify API documentation** - What units does the source use?
- [ ] **Check sample data** - Run API call manually, inspect response
- [ ] **Document quirks** - Note any inversions, scalings, seasonal adjustments
- [ ] **Add to metadata** - Update `series_attributes` table with notes

## Post-Ingestion (After First Load)

- [ ] **Spot check values** - Do the numbers "make sense"?
- [ ] **Compare to source** - Match 3-5 random observations against API/website
- [ ] **Check date ranges** - Does earliest/latest match expectations?
- [ ] **Validate NULL handling** - Are missing values represented correctly?

## For FX Rates Specifically

- [ ] **Determine direction** - Is it `USD per FX` or `FX per USD`?
- [ ] **Test inversion** - Does `1 / value` give expected result?
- [ ] **Cross-validate** - Compare to other sources (e.g., FRED vs. Bloomberg)
- [ ] **Document in view** - Add to `analytics.fx_rates_normalized`

## For Economic Indicators

- [ ] **Verify frequency** - Is it D, W, M, Q, A?
- [ ] **Check seasonality** - Is it SA (seasonally adjusted) or NSA?
- [ ] **Validate units** - Billions? Millions? Index (base year)?
- [ ] **Confirm geography** - USA, EUR, CAN, etc.

## Quarterly Review (Every 3 Months)

- [ ] **Run data quality dashboard** - Check `analytics.data_quality_dashboard`
- [ ] **Review staleness** - Are any series not updating?
- [ ] **Audit transformations** - Are any views producing unexpected results?
- [ ] **Update documentation** - Reflect any schema changes

## Red Flags to Watch For

🚩 **FX rate suddenly > 10 or < 0.1** (likely inversion issue)  
🚩 **Values jump by >50% between observations** (check for unit changes)  
🚩 **NULL percentage > 5%** (investigate data gaps)  
🚩 **No updates in > 7 days** (for daily series - API issue?)  
🚩 **Date range doesn't match API docs** (incomplete backfill)
