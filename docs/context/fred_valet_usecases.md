# Project Chronos – FRED & Bank of Canada Valet Use Cases  
**Last Updated:** 2025-11-04  
**Purpose:** Define strategic, multi-modal analytical use cases leveraging the Chronos architecture and FRED/Valet APIs.

---

## Overview

Both **FRED (Federal Reserve Economic Data)** and **Bank of Canada Valet** provide high-frequency, high-quality macroeconomic data.  
When integrated into Chronos, they become foundational streams for:

- Econometric modeling  
- Geospatial and network correlation  
- Semantic intelligence linking indicators across modalities  
- Cross-country macro-financial comparison  

---

## High-Level Use Cases (with Technical Integration Concepts)

### 1. **Cross-Border Monetary Correlation Network**
**Goal:** Detect correlation networks between Canadian and U.S. monetary indicators.  
**Approach:**  
- Ingest `FRED` interest rate and monetary base series.  
- Ingest `Valet` FX and money supply data.  
- Use Apache AGE to build graph relationships between indicators via Pearson correlation edges.  
- Store and query using Cypher within SQL.

---

### 2. **Spatial Inflation Mapping**
**Goal:** Visualize inflation rates by province or state, linked to trade corridors.  
**Approach:**  
- Map FRED CPI data by U.S. region using PostGIS polygons.  
- Overlay Valet inflation and FX data by Canadian province.  
- Use `ST_Intersects` and `ST_Distance` to compute inflation similarity across borders.

---

### 3. **Vectorized Policy Embedding Search**
**Goal:** Find similar central bank policy statements.  
**Approach:**  
- Use `pgvector` to store text embeddings of Bank of Canada and Federal Reserve press releases.  
- Query by cosine similarity to find semantically aligned statements.  
- Join with `fred.series_metadata` to contextualize policy sentiment shifts.

---

### 4. **Regime Detection via MADlib**
**Goal:** Detect economic regimes (e.g., expansion, contraction).  
**Approach:**  
- Use `madlib.kmeans()` or `madlib.linregr_train()` on TimescaleDB series of GDP, CPI, and employment.  
- Classify clusters and store “regime labels” as new table attributes.  
- Integrate with semantic embeddings for “policy tone” weighting.

---

### 5. **Trade-Weighted Currency Dashboard**
**Goal:** Compute a live, geospatially weighted CAD/USD index.  
**Approach:**  
- Combine Valet FX data with PostGIS country polygons weighted by trade volume (via AGE graph edges).  
- Use Timescale continuous aggregates for rolling averages.  
- Expose to Evidence dashboard via SQL queries.

---

### 6. **Semantic Series Alignment**
**Goal:** Discover related indicators across FRED and Valet via textual similarity.  
**Approach:**  
- Use `pgvector` embeddings of series names/descriptions.  
- Run cross-database semantic joins:

```sql
SELECT 
  f.series_id, 
  v.series_id, 
  cosine_similarity(f.embedding, v.embedding) AS similarity
FROM fred.series_embeddings f
JOIN valet.series_embeddings v 
  ON cosine_similarity(f.embedding, v.embedding) > 0.8;

7. Graph-Driven Lead-Lag Analysis

Goal: Identify which indicators lead or lag others temporally.
Approach:

    Use AGE graph edges to represent lead-lag relationships (e.g., via Granger causality).

    Store edge weights as correlation coefficients.

    Query for “central” indicators driving network dynamics using Cypher.

8. FX Volatility and Geo-Sentiment Fusion

Goal: Merge quantitative FX volatility with text sentiment and geography.
Approach:

    Compute volatility via plpython3u using numpy.std() within time windows.

    Combine with semantic embeddings of news headlines.

    Visualize on PostGIS maps, coloring regions by volatility clusters.

9. Monetary Policy Transmission Graph

Goal: Model how policy changes propagate through economic networks.
Approach:

    Represent macroeconomic variables as graph nodes (interest rates, CPI, employment, FX).

    Represent causal or lag relationships as weighted edges.

    Query network centrality using Cypher for indicators with the strongest transmission effects.

10. API-Driven Real-Time Refresh Layer

Goal: Maintain continuously updated datasets from FRED and Valet.
Approach:

    Use http and plpython3u extensions for periodic API synchronization.

    Schedule refreshes via pg_cron or external Docker tasks.

    Store metadata lineage for each update batch for full reproducibility.

Implementation Pattern Summary
Layer	Technology	Function
Ingestion	FDW, HTTP, plpython3u	Real-time API ingestion from FRED and Valet
Storage	TimescaleDB	Time-series hypertables and continuous aggregates
Analytics	MADlib, plpython3u	In-database statistical and econometric modeling
Network / Graph	Apache AGE	Causal and relational modeling of indicators
Spatial	PostGIS	Geographic and border-based data correlation
Semantic	pgvector	Text and embedding similarity for semantic alignment
Visualization	Evidence, Metabase	Reporting and analytical UI integration
Future Directions

    Add cross-language embeddings to align English/French Canadian economic texts.

    Integrate PostgresML or TensorFlow FDW for hybrid in-database model training.

    Extend graph schema to represent global trade linkages (IMF, OECD).

    Add event-based triggers for automated “economic regime change” alerts.
