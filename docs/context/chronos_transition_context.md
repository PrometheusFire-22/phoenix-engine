# Project Chronos – Transition Context (Claude Browser → Claude Code)
**Last Updated:** 2025-11-04  
**Purpose:** Capture architectural vision and technical background for Claude Code local session.

---

## Vision

Project Chronos aims to become an **extensible, multi-modal financial and economic intelligence database** built on PostgreSQL.  
The design philosophy is to **maximize extensibility at the database layer first**, before layering business logic, analytics views, and API interfaces.

This means establishing first-class support for:
- **Time-series analytics** via TimescaleDB  
- **Geospatial intelligence** via PostGIS  
- **Graph relationships** via Apache AGE  
- **Semantic similarity and embeddings** via pgvector  
- Additional modality extensions to follow (columnar, document, etc.)

Once these data modalities are active and verifiable inside the Dockerized PostgreSQL environment, development will shift toward:
1. Building out **schemas and relationships** for each modality.  
2. Designing **analytics views** and **business logic**.  
3. Developing **multi-modal insights** that combine these data types.  

---

## Technical Ecosystem

- **OS / Environment:** Ubuntu + Docker + VS Code Dev Containers  
- **Core Database:** PostgreSQL 16.4 with TimescaleDB, PostGIS, Apache AGE, pgvector  
- **Extensions Philosophy:** Use PostgreSQL as a “data OS” that unifies structured, temporal, geospatial, semantic, and relational data.  
- **Infrastructure:** Git + GitHub Actions for CI/CD, SQLTools for exploration, Evidence and Metabase planned for visualization.  

The project is already stable at the container level (see “Project Chronos – Context Transfer”), and the next step is deepening schema design for PostGIS, AGE, and pgvector.

---

## Transition Goals (Claude Browser → Claude Code)

1. **Load Context**
   - Claude Code should read this file and `project-chronos/Project_Chronos_Context_Transfer.md` to have full architectural and operational awareness.

2. **Assist With Schema Expansion**
   - Design new schemas/tables that leverage PostGIS, AGE, and pgvector data types.
   - Maintain compatibility with existing `metadata` and `timeseries` schemas.

3. **Generate Business Logic & Views**
   - Develop SQL materialized views and stored procedures that combine multiple modalities.
   - Example: correlate geospatial proximity with semantic similarity scores.

4. **Aid in Docker & Dev-Container Integration**
   - Ensure PostgreSQL builds correctly with all multi-modal extensions.
   - Assist with `docker-compose.yml` or `Dockerfile.timescaledb` refinements.

5. **Future Phase**
   - Help build analytical APIs (PostgREST or Hasura).
   - Create Evidence dashboards using Markdown + SQL.

---

## Design Emphasis

- **Data as a platform:** treat PostgreSQL as a hub capable of ingesting and reasoning across modalities.  
- **Schema clarity:** each modality should have a clear, isolated schema with foreign-key bridges to `metadata.series_metadata`.  
- **Extensibility first:** once core modal schemas are mature, add derivative schemas (text, network, trade, etc.).  
- **Versioning & governance:** use pgMemento/pgaudit later for lineage and reproducibility.

---

## Next Conversation Topics

1. Generate initial schema definitions for:
   - `geospatial.series_regions` (PostGIS)
   - `graph.economic_relationships` (Apache AGE)
   - `semantic.series_embeddings` (pgvector)

2. Create examples of **cross-modality analytical views**.

3. Brainstorm **business and analytical use cases** using:
   - **FRED API** (U.S. economic indicators)
   - **Bank of Canada Valet API** (FX and monetary data)

---

> After this file is loaded, continue by asking Claude Code to:
> ```
> /read context/Project_Chronos_Context_Transfer.md
> /read context/chronos_transition_context.md
> ```
> Then begin the discussion about schema design, view creation, and business logic for FRED and Valet data.
