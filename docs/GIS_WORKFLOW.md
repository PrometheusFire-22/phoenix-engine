# Project Chronos: GIS Data Processing Workflow

This document outlines the standard operating procedure for processing raw geospatial boundary files for use in the Chronos database.

**Guiding Principles:**
1.  **Temporal Alignment:** Geographic data vintage must match the statistical data vintage (e.g., 2024 TIGER files for 2024 ACS data).
2.  **Performance:** Geometries must be simplified to ensure efficient database queries and rendering.
3.  **Schema Minimalism:** Only essential attribute columns (`GEOID`, `NAME`, etc.) should be retained to keep the database schema clean.
4.  **Reproducibility:** The final output is a database-ready `.geojson` file in the `gis_data/processed/` directory.

---
## Standard Processing Steps

This procedure is performed in QGIS on the native OS.

**Example Layer:** `2024 U.S. Counties`

1.  **Acquisition:**
    *   Source: 2024 TIGER/Line Shapefiles Web Interface.
    *   Downloaded File: `tl_2024_us_county.zip`.
    *   Saved to: `gis_data/raw/`.

2.  **Initial Load & Filtering:**
    *   The raw `.shp` file is loaded into the QGIS project.
    *   A filter is applied to exclude territories and focus on the continental US.
    *   **Filter Expression:** `"STATEFP" <= '56'`

3.  **Attribute Cleaning:**
    *   Open the attribute table.
    *   Enable editing and delete all columns except for the following essential identifiers:
        *   `GEOID`
        *   `NAME`
        *   `NAMELSAD` (Name with legal/statistical description)
        *   `STATEFP`

4.  **Geometry Simplification:**
    *   Tool: `Vector -> Geometry Tools -> Simplify`.
    *   **Tolerance:** `0.01` (degrees). This provides a >80% size reduction with negligible visual impact at a national scale.

5.  **Final Export:**
    *   The "Simplified" layer is exported.
    *   **Format:** `GeoJSON`
    *   **CRS:** `EPSG:4326 - WGS 84`
    *   **Output File:** `gis_data/processed/us_counties_2024.geojson`

---
