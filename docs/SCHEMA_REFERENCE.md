# Database Schema Reference

## Quick Schema Diagram
```
metadata schema
├── data_sources (API registry)
│   └── source_id → used by all other tables
├── series_metadata (time-series definitions)
│   ├── series_id (PK, UUID)
│   └── source_id (FK → data_sources)
├── series_attributes (flexible metadata)
│   └── series_id (FK → series_metadata)
└── ingestion_log (audit trail)
    └── source_id (FK → data_sources)

timeseries schema
└── economic_observations (HYPERTABLE)
    ├── series_id (FK → series_metadata)
    └── source_id (FK → data_sources)
```

## Table Definitions

### `metadata.data_sources`

**Purpose:** Registry of all external data providers

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| source_id | SERIAL | PRIMARY KEY | Auto-incrementing ID |
| source_name | VARCHAR(100) | UNIQUE, NOT NULL | Display name (e.g., 'FRED') |
| api_type | VARCHAR(50) | NOT NULL | Protocol type (rest, sdmx, graphql) |
| base_url | TEXT | NOT NULL | API endpoint base URL |
| requires_auth | BOOLEAN | DEFAULT FALSE | Does API need credentials? |
| is_active | BOOLEAN | DEFAULT TRUE | Is source currently enabled? |
| rate_limit_rpm | INTEGER | NULL | Requests per minute limit |
| notes | TEXT | NULL | Additional config notes |
| created_at | TIMESTAMPTZ | DEFAULT NOW() | Row creation timestamp |
| updated_at | TIMESTAMPTZ | DEFAULT NOW() | Last update timestamp |

**Indexes:**
- `idx_data_sources_active` on `is_active` (partial index WHERE is_active = TRUE)

**Example Query:**
```sql
SELECT source_name, api_type, requires_auth 
FROM metadata.data_sources 
WHERE is_active = TRUE;
```

---

### `metadata.series_metadata`

**Purpose:** Central registry of all time-series being tracked

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| series_id | UUID | PRIMARY KEY | Unique series identifier (auto-generated) |
| source_id | INTEGER | FK → data_sources | Which API provides this series |
| source_series_id | VARCHAR(255) | NOT NULL | Native ID from source (e.g., 'GDP') |
| series_name | TEXT | NOT NULL | Human-readable name |
| series_description | TEXT | NULL | Full description from source |
| frequency | VARCHAR(20) | NULL | D, W, M, Q, A, etc. |
| units | VARCHAR(100) | NULL | e.g., 'Billions USD', 'Index' |
| seasonal_adjustment | VARCHAR(50) | NULL | SA, NSA, SAAR |
| geography | VARCHAR(100) | NULL | Country/region code |
| last_updated | TIMESTAMPTZ | NULL | When we last fetched data |
| is_active | BOOLEAN | DEFAULT TRUE | Can be disabled without deletion |
| created_at | TIMESTAMPTZ | DEFAULT NOW() | Row creation timestamp |
| updated_at | TIMESTAMPTZ | DEFAULT NOW() | Last update timestamp |

**Constraints:**
- `UNIQUE(source_id, source_series_id)` - No duplicate series from same source

**Indexes:**
- `idx_series_source` on `source_id`
- `idx_series_geography` on `geography`
- `idx_series_frequency` on `frequency`
- `idx_series_active` on `is_active` (partial index WHERE is_active = TRUE)

**Example Query:**
```sql
SELECT 
    source_series_id, 
    series_name, 
    frequency, 
    units
FROM metadata.series_metadata
WHERE geography = 'USA' AND frequency = 'Q';
```

---

### `metadata.series_attributes`

**Purpose:** Flexible key-value store for source-specific metadata

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| attribute_id | SERIAL | PRIMARY KEY | Auto-incrementing ID |
| series_id | UUID | FK → series_metadata | Which series this attribute belongs to |
| attribute_key | VARCHAR(100) | NOT NULL | Attribute name |
| attribute_value | TEXT | NULL | Attribute value |
| created_at | TIMESTAMPTZ | DEFAULT NOW() | Row creation timestamp |

**Constraints:**
- `UNIQUE(series_id, attribute_key)` - One value per key per series
- `ON DELETE CASCADE` - Attributes deleted when series deleted

**Indexes:**
- `idx_series_attributes_lookup` on `(series_id, attribute_key)`

**Example Use Cases:**
- Store FRED's `realtime_start` and `realtime_end`
- Store ECB's `DECIMALS` precision
- Store custom tags/categories

**Example Query:**
```sql
SELECT attribute_key, attribute_value
FROM metadata.series_attributes
WHERE series_id = 'a1b2c3d4-...';
```

---

### `metadata.ingestion_log`

**Purpose:** Audit trail of all data ingestion operations

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| log_id | SERIAL | PRIMARY KEY | Auto-incrementing ID |
| source_id | INTEGER | FK → data_sources | Which API was called |
| ingestion_start | TIMESTAMPTZ | NOT NULL | When job started |
| ingestion_end | TIMESTAMPTZ | NULL | When job completed |
| status | VARCHAR(20) | NOT NULL | success, partial, failed |
| series_count | INTEGER | NULL | Number of series processed |
| records_inserted | INTEGER | NULL | Observations written |
| records_updated | INTEGER | NULL | Observations replaced |
| date_range_start | DATE | NULL | Requested start date |
| date_range_end | DATE | NULL | Requested end date |
| error_message | TEXT | NULL | If status = failed, why? |
| execution_metadata | JSONB | NULL | Script params, config, etc. |
| created_at | TIMESTAMPTZ | DEFAULT NOW() | Row creation timestamp |

**Indexes:**
- `idx_ingestion_source_date` on `(source_id, created_at DESC)`
- `idx_ingestion_status` on `status`

**Example Query:**
```sql
SELECT 
    log_id,
    status,
    series_count,
    records_inserted,
    ingestion_end - ingestion_start as duration
FROM metadata.ingestion_log
WHERE status = 'success'
ORDER BY log_id DESC
LIMIT 10;
```

---

### `timeseries.economic_observations` (HYPERTABLE)

**Purpose:** Core fact table storing all time-series observations

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| series_id | UUID | FK → series_metadata, PK | Which series this observation belongs to |
| observation_date | DATE | PK | Date of observation |
| value | NUMERIC(20,6) | NULL | Numeric value (handles wide range) |
| value_status | VARCHAR(20) | NULL | final, preliminary, revised |
| source_id | INTEGER | FK → data_sources | Which API provided this value |
| ingestion_timestamp | TIMESTAMPTZ | DEFAULT NOW() | When we recorded this value |

**Constraints:**
- `PRIMARY KEY (series_id, observation_date)` - No duplicate observations

**Indexes:**
- `idx_obs_series_date` on `(series_id, observation_date DESC)`
- `idx_obs_source` on `source_id`

**TimescaleDB Features:**
- **Hypertable:** Automatically partitioned by `observation_date` into 1-year chunks
- **Chunk Interval:** 1 year (configurable)
- **Compression:** Can enable compression on old chunks to save space
- **Continuous Aggregates:** Can create materialized views for common aggregations

**Example Queries:**
```sql
-- Get all observations for a series
SELECT observation_date, value
FROM timeseries.economic_observations eo
JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
WHERE sm.source_series_id = 'GDP'
ORDER BY observation_date DESC;

-- Get observations for a date range (optimized by hypertable partitioning)
SELECT observation_date, value
FROM timeseries.economic_observations
WHERE series_id = 'a1b2c3d4-...'
  AND observation_date BETWEEN '2020-01-01' AND '2024-12-31'
ORDER BY observation_date;

-- Upsert pattern (used by ingestion scripts)
INSERT INTO timeseries.economic_observations (
    series_id, observation_date, value, source_id
)
VALUES ('a1b2c3d4-...', '2024-10-27', 28174.30, 1)
ON CONFLICT (series_id, observation_date)
DO UPDATE SET 
    value = EXCLUDED.value,
    ingestion_timestamp = NOW();
```

---

## Helper Views

### `timeseries.latest_observations`

**Purpose:** Quick access to most recent observation for each series

**Definition:**
```sql
CREATE OR REPLACE VIEW timeseries.latest_observations AS
SELECT DISTINCT ON (series_id)
    series_id,
    observation_date,
    value,
    value_status
FROM timeseries.economic_observations
ORDER BY series_id, observation_date DESC;
```

**Usage:**
```sql
SELECT 
    sm.source_series_id,
    lo.observation_date,
    lo.value
FROM timeseries.latest_observations lo
JOIN metadata.series_metadata sm ON lo.series_id = sm.series_id;
```

---

### `metadata.series_summary`

**Purpose:** Comprehensive overview of all series with statistics

**Definition:**
```sql
CREATE OR REPLACE VIEW metadata.series_summary AS
SELECT
    sm.series_id,
    ds.source_name,
    sm.source_series_id,
    sm.series_name,
    sm.frequency,
    sm.units,
    sm.geography,
    sm.is_active,
    COUNT(eo.observation_date) AS observation_count,
    MIN(eo.observation_date) AS earliest_date,
    MAX(eo.observation_date) AS latest_date
FROM metadata.series_metadata sm
LEFT JOIN metadata.data_sources ds ON sm.source_id = ds.source_id
LEFT JOIN timeseries.economic_observations eo ON sm.series_id = eo.series_id
GROUP BY sm.series_id, ds.source_name, sm.source_series_id, sm.series_name, 
         sm.frequency, sm.units, sm.geography, sm.is_active;
```

**Usage:**
```sql
SELECT * FROM metadata.series_summary ORDER BY observation_count DESC;
```

---

## Performance Optimization Tips

### 1. Always Filter by Date When Possible
```sql
-- GOOD: Uses hypertable partitioning
SELECT * FROM timeseries.economic_observations
WHERE observation_date >= '2020-01-01';

-- BAD: Scans all partitions
SELECT * FROM timeseries.economic_observations
WHERE value > 1000;
```

### 2. Use series_id for Joins (Not source_series_id)
```sql
-- GOOD: Direct FK join
SELECT * FROM timeseries.economic_observations
WHERE series_id = 'a1b2c3d4-...';

-- LESS EFFICIENT: Requires join to series_metadata first
SELECT * FROM timeseries.economic_observations eo
JOIN metadata.series_metadata sm ON eo.series_id = sm.series_id
WHERE sm.source_series_id = 'GDP';
```

### 3. Use EXPLAIN ANALYZE for Complex Queries
```sql
EXPLAIN ANALYZE
SELECT /* your query */;
```

Look for:
- "Index Scan" (good) vs "Seq Scan" (bad for large tables)
- "Chunks excluded" (TimescaleDB partition pruning)