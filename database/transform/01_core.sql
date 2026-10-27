-- raw -> core  (full refresh, one transaction) raw stays untouched. Rows that cannot enter core are logged
-- to core.data_quality_issues instead of being dropped silently.


BEGIN;

TRUNCATE TABLE
    core.generation,
    core.plants,
    core.countries,
    core.fuels,
    core.data_quality_issues,
    analytics.country_energy_summary
RESTART IDENTITY;

-- Countries -------------------------------------------------
INSERT INTO core.countries (country_code, country_name)
SELECT country_code, MIN(country_long)
FROM raw.power_plants
WHERE country_code IS NOT NULL
GROUP BY country_code;

-- Fuels (category mapping ) -----------------------
INSERT INTO core.fuels (fuel_name, fuel_category)
SELECT DISTINCT
    primary_fuel,
    CASE
        WHEN primary_fuel IN ('Solar','Hydro','Wind','Biomass','Geothermal','Wave and Tidal')
            THEN 'Renewable'
        WHEN primary_fuel IN ('Coal','Gas','Oil','Nuclear','Petcoke')
            THEN 'Non-Renewable'
        ELSE 'Other'   -- Waste, Storage, Cogeneration, Other, anything new
    END
FROM raw.power_plants
WHERE primary_fuel IS NOT NULL;

-- Rows that cannot enter core.plants -------------------------
INSERT INTO core.data_quality_issues (rule, severity, raw_id, detail)
SELECT 'rejected_invalid_row', 'error', raw_id,
       'Failed a core.plants rule (missing/invalid country, fuel, capacity, coordinates or start year)'
FROM raw.power_plants r
WHERE NOT (
        r.country_code IS NOT NULL
    AND r.primary_fuel IS NOT NULL
    AND r.plant_name   IS NOT NULL
    AND r.capacity_mw  IS NOT NULL AND r.capacity_mw >= 0
    AND r.latitude  BETWEEN -90  AND 90
    AND r.longitude BETWEEN -180 AND 180
    AND (r.start_year_raw IS NULL OR FLOOR(r.start_year_raw) BETWEEN 1800 AND 2100)
);

-- Plants ----------------------------------------------------
INSERT INTO core.plants (
    country_id, fuel_id, plant_name, capacity_mw, latitude, longitude,
    start_year_raw, start_year, owner, geolocation_source, source_raw_id
)
SELECT
    c.country_id, f.fuel_id, r.plant_name, r.capacity_mw, r.latitude, r.longitude,
    r.start_year_raw, FLOOR(r.start_year_raw)::INTEGER, r.owner, r.geolocation_source, r.raw_id
FROM raw.power_plants r
JOIN core.countries c ON c.country_code = r.country_code
JOIN core.fuels     f ON f.fuel_name    = r.primary_fuel
WHERE r.plant_name IS NOT NULL
  AND r.capacity_mw IS NOT NULL AND r.capacity_mw >= 0
  AND r.latitude  BETWEEN -90  AND 90
  AND r.longitude BETWEEN -180 AND 180
  AND (r.start_year_raw IS NULL OR FLOOR(r.start_year_raw) BETWEEN 1800 AND 2100);

-- Generation (2021) -----------------------------------------
INSERT INTO core.generation (plant_id, generation_year, actual_generation_gwh, estimated_generation_gwh)
SELECT p.plant_id, 2021, r.generation_gwh_2021, r.estimated_generation_gwh_2021
FROM raw.power_plants r
JOIN core.plants p ON p.source_raw_id = r.raw_id
WHERE r.generation_gwh_2021 IS NOT NULL
   OR r.estimated_generation_gwh_2021 IS NOT NULL;

COMMIT;
