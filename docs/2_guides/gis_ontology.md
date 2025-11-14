Here is the text converted into attractive markdown:

## 🗺️ The Geographic Granularity Ontology

Your concern about "**State**" versus "**Province**" is critical. The solution is to use a **standardized, abstract vocabulary** that is not country-specific. This is our new controlled vocabulary for granularity:

| Term | Definition | US Example | Canadian Example |
| :--- | :--- | :--- | :--- |
| **national** | A single file containing boundaries for the entire country. | `us_states` | `ca_provinces_territories` |
| **admin\_1** | The first-level administrative division (states, provinces). | `us_tracts` (split by state) | `ca_dissemination_areas` (split by province) |
| **admin\_2** | The second-level administrative division (counties, census divisions). | (Future use) | (Future use) |
| **local** | The most granular levels (municipalities, zip codes). | (Future use) | (Future use) |

---

### 🗃️ Impact on Directory Structure

This ontology makes our directory structure universally applicable. The existing **state folder** will now be renamed to **admin\_1**.

```
gis_data/raw/USA/
└── admin_1/  # <--- Was 'state'
    └── TRACT/
        ├── zipped/
        └── unzipped/
```
