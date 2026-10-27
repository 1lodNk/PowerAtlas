-- core -> analytics  (full refresh)

BEGIN;

TRUNCATE TABLE analytics.country_energy_summary;

INSERT INTO analytics.country_energy_summary (
    country_id, country_code, country_name,
    plant_count, total_capacity_mw,
    actual_generation_gwh, estimated_generation_gwh,
    renewable_capacity_mw, renewable_capacity_share
)
SELECT
    c.country_id,
    c.country_code,
    c.country_name,
    COUNT(p.plant_id),
    SUM(p.capacity_mw),
    SUM(g.actual_generation_gwh),       -- NULL where a country has no actuals
    SUM(g.estimated_generation_gwh),
    COALESCE(SUM(p.capacity_mw) FILTER (WHERE f.fuel_category = 'Renewable'), 0),
    COALESCE(SUM(p.capacity_mw) FILTER (WHERE f.fuel_category = 'Renewable'), 0)
        / NULLIF(SUM(p.capacity_mw), 0)
FROM core.countries c
JOIN core.plants p ON p.country_id = c.country_id
JOIN core.fuels  f ON f.fuel_id    = p.fuel_id
LEFT JOIN core.generation g ON g.plant_id = p.plant_id AND g.generation_year = 2021
GROUP BY c.country_id, c.country_code, c.country_name;

COMMIT;
