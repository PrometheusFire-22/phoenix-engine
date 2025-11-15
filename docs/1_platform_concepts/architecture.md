# 🏛️ Project Chronos: System Architecture

**Version:** 2.1
**Last Updated:** 2025-11-14
**Status:** ✅ Implemented & Stable

This document provides a comprehensive overview of the architecture for Project Chronos, a multi-modal macroeconomic and financial data platform. It details the guiding principles, components, data flows, and design decisions that define the system.

## 1. C4 Model: A Layered View

We use the [C4 Model](https://c4model.com/) to describe the architecture at different levels of abstraction.

### Level 1: System Context

This diagram shows how Project Chronos fits into its ecosystem, interacting with users, tools, and external data providers.

```mermaid
graph TD
    subgraph "Users & Tools"
        direction LR
        A[👩‍💻 Financial Analyst]
        B[📊 Metabase]
        C[🐘 pgAdmin4]
    end

    subgraph "Project Chronos"
        P[<b style='font-size:1.2em'>Project Chronos</b><br/>Multi-modal economic data platform.]
    end

    subgraph "External Data Sources"
        direction LR
        D[🏦 FRED API]
        E[🏦 Valet API]
        F[🗺️ US Census TIGER/Line]
        G[🗺️ Statistics Canada]
    end

    A -- "Uses" --> P
    A -- "Analyzes via" --> B
    A -- "Administers via" --> C

    B -- "Queries [SQL]" --> P
    C -- "Manages [SQL]" --> P

    P -- "Ingests Time-Series Data" --> D & E
    P -- "Ingests Geospatial Data" --> F & G
```

### Level 2: Container Diagram

This diagram zooms into Project Chronos, showing the major deployable components (containers) and their responsibilities.

```mermaid
graph TD
    subgraph "User Interfaces"
        metabase["<b style='font-size:1em'>Metabase BI Tool</b><br/>(chronos-metabase)<br/>Web UI for ad-hoc data exploration and dashboarding."]
        dash["<b style='font-size:1em'>Plotly Dash Frontend</b><br/>(Future)<br/>Custom, interactive web application for presenting curated insights."]
    end
    
    subgraph "Core System"
        app["<b style='font-size:1em'>Application Container</b><br/>(chronos-app)<br/>Python environment for data ingestion, scripting, and future API hosting."]
        db["<b style='font-size:1em'>Database Container</b><br/>(chronos-db)<br/>Multi-modal data warehouse and analytical engine."]
    end

    subgraph "External Data Sources"
        apis["APIs<br/>(FRED, Valet, etc.)"]
    end

    app -- "Ingests data from" --> apis
    app -- "Writes data to [SQL]" --> db
    metabase -- "Reads data from [SQL]" --> db
    dash -- "Will read data from [SQL]" --> db

    style app fill:#d4edda
    style db fill:#cce5ff
    style metabase fill:#f8d7da
```

### Level 3: Component Diagram (Database)

This diagram zooms into the **Database Container**, showing how PostgreSQL is extended to create our multi-modal capabilities.

```mermaid
graph LR
    subgraph "PostgreSQL 16 Core"
        Core["Storage &<br/>Query Engine"]
    end
    
    subgraph "Installed Extensions"
        TS["<b>TimescaleDB</b><br/>Time-series hypertables,<br/>continuous aggregates"]
        GIS["<b>PostGIS</b><br/>Geospatial types (geometry)<br/>and functions"]
        VEC["<b>pgvector</b><br/>Vector embedding storage<br/>and similarity search"]
        AGE["<b>Apache AGE</b><br/>OpenCypher graph database"]
    end

    subgraph "Logical Schemas"
        S_TS[<b>timeseries</b><br/>Raw economic observations]
        S_GIS[<b>boundaries</b><br/>Geospatial vector data]
        S_META[<b>metadata</b><br/>Series definitions & logs]
        S_ANALYTICS[<b>analytics</b><br/>Views & Functions]
    end

    TS & GIS & VEC & AGE -- "Extend" --> Core
    Core -- "Organized into" --> S_TS & S_GIS & S_META & S_ANALYTICS
```

## 2. Data Flow & Logic

### Ingestion Flow

The data ingestion process is automated via a suite of version-controlled scripts, designed to be robust and auditable.

```mermaid
sequenceDiagram
    participant User
    participant Script as "Bash Script<br/>(e.g., bulk_ingest_fred.sh)"
    participant Python as "Python Script<br/>(e.g., ingest_fred.py)"
    participant Ingestor as "Ingestor Class"
    participant DB as "Chronos DB"

    User->>Script: Executes script
    Script->>Python: Runs with parameters
    activate Python
    Python->>DB: INSERT into ingestion_log (status='running')
    Python->>Ingestor: fetch/register/store
    activate Ingestor
    Ingestor-->>DB: INSERT data (ON CONFLICT)
    deactivate Ingestor
    Python->>DB: UPDATE ingestion_log (status='success')
    deactivate Python
```

### Analytical Logic Layers 

Our architecture pushes complex logic down into the database, ensuring consistency and performance for all data consumers.

```mermaid
graph BT
    subgraph "Data Consumers"
        A[📊 Metabase]
        B[🐍 Python Reports]
        C[⚡ Future API]
    end
    
    subgraph "Analytical Layers (in PostgreSQL)"
        L4["<b>Layer 4:</b><br/>Functions<br/>(e.g., calculate_yoy_growth)"]
        L3["<b>Layer 3:</b><br/>Aggregates<br/>(e.g., fx_daily_summary)"]
        L2["<b>Layer 2:</b><br/>Insight Views<br/>(e.g., v_admin_1_boundaries)"]
        L1["<b>Layer 1:</b><br/>Normalization Views<br/>(e.g., fx_rates_normalized)"]
    end

    subgraph "Raw Data Schemas"
        D[timeseries]
        E[boundaries]
    end

    A & B & C -- "Query" --> L4 & L3 & L2
    L4 & L3 & L2 -- "Build upon" --> L1
    L1 -- "Abstracts" --> D & E
```
