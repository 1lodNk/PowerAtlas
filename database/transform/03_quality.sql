-- ============================================================
-- Data quality checks on core  (findings -> core.data_quality_issues)
-- Capacity factor = actual GWh * 1000 / (capacity MW * 8760 h)
-- Only plants with actual generation (US, EIA) can be checked.
-- Runs after 01_core.sql, which clears the issues table.
-- ============================================================


BEGIN;

-- (rejected_invalid_row findings belong to 01_core.sql and are kept.)
DELETE FROM core.data_quality_issues WHERE rule <> 'rejected_invalid_row';

CREATE TEMP TABLE _cf ON COMMIT DROP AS
SELECT
    p.plant_id,
    p.source_raw_id,
    p.plant_name,
    p.capacity_mw,
    f.fuel_name,
    g.actual_generation_gwh,
    g.actual_generation_gwh * 1000.0 / NULLIF(p.capacity_mw * 8760, 0) AS capacity_factor
FROM core.plants p
JOIN core.fuels f      ON f.fuel_id = p.fuel_id
JOIN core.generation g ON g.plant_id = p.plant_id AND g.generation_year = 2021
WHERE g.actual_generation_gwh IS NOT NULL;


-- Physically impossible: produced >110% of nameplate in a year
INSERT INTO core.data_quality_issues (rule, severity, raw_id, plant_id, detail)
SELECT 'capacity_factor_impossible', 'error', source_raw_id, plant_id,
       format('%s (%s): %s GWh from %s MW = capacity factor %s',
              plant_name, fuel_name, round(actual_generation_gwh::numeric, 1),
              capacity_mw, round(capacity_factor::numeric, 2))
FROM _cf WHERE capacity_factor > 1.10;


-- Slightly above nameplate: usually upgrades or outdated capacity
INSERT INTO core.data_quality_issues (rule, severity, raw_id, plant_id, detail)
SELECT 'capacity_factor_above_nameplate', 'info', source_raw_id, plant_id,
       format('%s (%s): capacity factor %s', plant_name, fuel_name, round(capacity_factor::numeric, 3))
FROM _cf WHERE capacity_factor > 1.00 AND capacity_factor <= 1.10;


-- Implausibly high for the fuel (solar and wind have natural ceilings)
INSERT INTO core.data_quality_issues (rule, severity, raw_id, plant_id, detail)
SELECT 'capacity_factor_high_for_fuel', 'warning', source_raw_id, plant_id,
       format('%s (%s): capacity factor %s', plant_name, fuel_name, round(capacity_factor::numeric, 2))
FROM _cf
WHERE capacity_factor <= 1.10
  AND ((fuel_name = 'Solar' AND capacity_factor > 0.45)
    OR (fuel_name = 'Wind'  AND capacity_factor > 0.70));


-- Large baseload plant reporting zero output
INSERT INTO core.data_quality_issues (rule, severity, raw_id, plant_id, detail)
SELECT 'zero_generation_baseload', 'warning', source_raw_id, plant_id,
       format('%s (%s, %s MW) reported 0 GWh', plant_name, fuel_name, capacity_mw)
FROM _cf
WHERE actual_generation_gwh = 0 AND capacity_mw >= 100
  AND fuel_name IN ('Coal','Nuclear','Hydro','Geothermal','Biomass','Waste');


-- Negative generation is expected for storage; anything else is suspicious
INSERT INTO core.data_quality_issues (rule, severity, raw_id, plant_id, detail)
SELECT 'negative_generation_non_storage', 'warning', source_raw_id, plant_id,
       format('%s (%s): %s GWh', plant_name, fuel_name, round(actual_generation_gwh::numeric, 3))
FROM _cf
WHERE actual_generation_gwh < 0 AND fuel_name <> 'Storage';

COMMIT;

-- Reporting views

CREATE OR REPLACE VIEW analytics.dq_rule_summary AS
SELECT rule, severity, COUNT(*) AS issue_count
FROM core.data_quality_issues
GROUP BY rule, severity
ORDER BY CASE severity WHEN 'error' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END, rule;

CREATE OR REPLACE VIEW analytics.dq_field_completeness AS
SELECT
    COUNT(*)                                                     AS plants,
    ROUND(100.0 * COUNT(start_year) / COUNT(*), 1)               AS pct_with_start_year,
    ROUND(100.0 * COUNT(owner)      / COUNT(*), 1)               AS pct_with_owner,
    ROUND(100.0 * (SELECT COUNT(*) FROM core.generation WHERE actual_generation_gwh IS NOT NULL)
          / COUNT(*), 1)                                         AS pct_with_actual_generation,
    ROUND(100.0 * (SELECT COUNT(*) FROM core.generation WHERE estimated_generation_gwh IS NOT NULL)
          / COUNT(*), 1)                                         AS pct_with_estimated_generation
FROM core.plants;