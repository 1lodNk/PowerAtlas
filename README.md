# PowerAtlas

End-to-end data pipeline for global power plant infrastructure analysis.
Source: the Global Power Plant Database (~35k plants, 167 countries).

## Architecture

```
CSV ──► raw.power_plants ──► core.* ──► analytics.*
         (untouched copy)    (clean,      (country summary,
                              modelled)    quality views)
                                  │
                                  └──► core.data_quality_issues
```

| Layer | What it holds |
|---|---|
| `raw` | Exact copy of the CSV plus load metadata. Never cleaned. |
| `core` | `countries`, `fuels` (with Renewable / Non-Renewable / Other category), `plants`, `generation`. |
| `analytics` | `country_energy_summary`, `data_quality_summary`, `field_completeness`. |

Rows that cannot enter `core` are logged in `core.data_quality_issues`, never silently dropped.

## Data quality checks

Capacity factor = actual generation (GWh) × 1000 / (capacity MW × 8760 h). Only US plants have actual generation, so checks apply to them.

| Rule | Severity | Meaning |
|---|---|---|
| `rejected_invalid_row` | error | Row could not enter `core` |
| `capacity_factor_impossible` | error | Output above 110% of nameplate |
| `capacity_factor_high_for_fuel` | warning | Solar above 45% or wind above 70% |
| `zero_generation_baseload` | warning | Coal, nuclear, hydro, etc. plant of 100 MW or more with 0 output |
| `negative_generation_non_storage` | warning | Negative output on a non-storage plant (negative is normal for storage) |
| `capacity_factor_above_nameplate` | info | Between 100% and 110% of nameplate |

## Setup

1. Copy `.env.example` to `.env` and fill in your Postgres credentials.
2. Create the `poweratlas` database and apply the schema:
   ```bash
   psql -U <user> -c "CREATE DATABASE poweratlas"
   psql -U <user> -d poweratlas -f database/schema.sql
   ```
   Already have the schema from an earlier version? Run
   `database/migrations/001_pipeline_updates.sql` instead.
3. Start Airflow: `docker compose up -d` and open http://localhost:8080.
4. Unpause and trigger the `poweratlas_pipeline` DAG:
   `ingest_raw → build_core → build_analytics → quality_checks`.

The transforms are plain SQL in `database/transform/` and can also be run directly with `psql -f`.
Every step is a full refresh, so re-running is safe.

## Useful queries

```sql
SELECT * FROM analytics.data_quality_summary;
SELECT * FROM analytics.field_completeness;
SELECT country_name, total_capacity_mw, renewable_capacity_share
FROM analytics.country_energy_summary ORDER BY total_capacity_mw DESC LIMIT 10;
```
