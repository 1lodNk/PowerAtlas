-- ============================================================
-- PowerAtlas
-- Global Power Plant Data Platform
-- Database Schema
-- ============================================================

-- ------------------------------------------------------------
-- Schemas
-- ------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS analytics;



-- RAW LAYER


CREATE TABLE IF NOT EXISTS raw.power_plants (
    raw_id BIGSERIAL PRIMARY KEY,

    country_code VARCHAR(10),
    country_long VARCHAR(150),
    plant_name VARCHAR(255),
    capacity_mw DOUBLE PRECISION,

    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,

    primary_fuel VARCHAR(100),
    secondary_fuel VARCHAR(100),
    other_fuel2 VARCHAR(100),
    other_fuel3 VARCHAR(100),

    start_year_raw NUMERIC(8,3),

    owner VARCHAR(500),

    generation_gwh_2021 DOUBLE PRECISION,
    geolocation_source VARCHAR(255),
    estimated_generation_gwh_2021 DOUBLE PRECISION,

    -- Pipeline metadata
    source_file VARCHAR(500),
    ingestion_timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);


-- ============================================================
-- CORE LAYER
-- ============================================================

-- Countries

CREATE TABLE IF NOT EXISTS core.countries (
    country_id BIGSERIAL PRIMARY KEY,

    country_code VARCHAR(10) NOT NULL,
    country_name VARCHAR(150) NOT NULL,

    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_country_code
        UNIQUE (country_code)
);


-- Fuel Types

CREATE TABLE IF NOT EXISTS core.fuels (
    fuel_id BIGSERIAL PRIMARY KEY,

    fuel_name VARCHAR(100) NOT NULL,

    fuel_category VARCHAR(50) NOT NULL,

    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_fuel_name
        UNIQUE (fuel_name),

    CONSTRAINT chk_fuel_category
        CHECK (
            fuel_category IN (
                'Renewable',
                'Non-Renewable',
                'Other'
            )
        )
);


-- Plants

CREATE TABLE IF NOT EXISTS core.plants (
    plant_id BIGSERIAL PRIMARY KEY,

    country_id BIGINT NOT NULL,
    fuel_id BIGINT NOT NULL,

    plant_name VARCHAR(255) NOT NULL,

    capacity_mw DOUBLE PRECISION NOT NULL,

    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,

    start_year_raw NUMERIC(8,3),
    start_year INTEGER,

    owner VARCHAR(500),
    geolocation_source VARCHAR(255),

    -- Link back to the raw row this plant was built from
    source_raw_id BIGINT,

    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_plant_country
        FOREIGN KEY (country_id)
        REFERENCES core.countries(country_id),

    CONSTRAINT fk_plant_fuel
        FOREIGN KEY (fuel_id)
        REFERENCES core.fuels(fuel_id),

    CONSTRAINT chk_capacity
        CHECK (capacity_mw >= 0),

    CONSTRAINT chk_latitude
        CHECK (latitude BETWEEN -90 AND 90),

    CONSTRAINT chk_longitude
        CHECK (longitude BETWEEN -180 AND 180),

    CONSTRAINT chk_start_year
        CHECK (
            start_year IS NULL
            OR start_year BETWEEN 1800 AND 2100
        )
);


-- Generation

CREATE TABLE IF NOT EXISTS core.generation (
    generation_id BIGSERIAL PRIMARY KEY,

    plant_id BIGINT NOT NULL,

    generation_year INTEGER NOT NULL,

    actual_generation_gwh DOUBLE PRECISION,
    estimated_generation_gwh DOUBLE PRECISION,

    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_generation_plant
        FOREIGN KEY (plant_id)
        REFERENCES core.plants(plant_id),

    CONSTRAINT chk_generation_year
        CHECK (
            generation_year BETWEEN 1900 AND 2100
        ),

    -- actual_generation_gwh may be negative: storage plants consume
    -- more energy than they produce, so no >= 0 rule here.

    CONSTRAINT chk_estimated_generation
        CHECK (
            estimated_generation_gwh IS NULL
            OR estimated_generation_gwh >= 0
        ),

    CONSTRAINT uq_plant_generation_year
        UNIQUE (plant_id, generation_year)
);


-- INDEXES

CREATE INDEX IF NOT EXISTS idx_countries_code
    ON core.countries(country_code);

CREATE INDEX IF NOT EXISTS idx_plants_country
    ON core.plants(country_id);

CREATE INDEX IF NOT EXISTS idx_plants_fuel
    ON core.plants(fuel_id);

CREATE INDEX IF NOT EXISTS idx_plants_coordinates
    ON core.plants(latitude, longitude);

CREATE INDEX IF NOT EXISTS idx_generation_plant
    ON core.generation(plant_id);

CREATE INDEX IF NOT EXISTS idx_generation_year
    ON core.generation(generation_year);

CREATE UNIQUE INDEX IF NOT EXISTS uq_plants_source_raw_id
    ON core.plants(source_raw_id);


-- Data quality findings (rebuilt on every pipeline run)

CREATE TABLE IF NOT EXISTS core.data_quality_issues (
    issue_id BIGSERIAL PRIMARY KEY,

    rule VARCHAR(100) NOT NULL,
    severity VARCHAR(20) NOT NULL,

    raw_id BIGINT,
    plant_id BIGINT,
    detail TEXT,

    detected_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_dq_severity
        CHECK (severity IN ('info', 'warning', 'error'))
);

CREATE INDEX IF NOT EXISTS idx_dq_rule
    ON core.data_quality_issues(rule);


-- ANALYTICS LAYER

CREATE TABLE IF NOT EXISTS analytics.country_energy_summary (
    country_id BIGINT PRIMARY KEY,

    country_code VARCHAR(10) NOT NULL,
    country_name VARCHAR(150) NOT NULL,

    plant_count INTEGER NOT NULL,
    total_capacity_mw DOUBLE PRECISION NOT NULL,

    actual_generation_gwh DOUBLE PRECISION,
    estimated_generation_gwh DOUBLE PRECISION,

    renewable_capacity_mw DOUBLE PRECISION,
    renewable_capacity_share DOUBLE PRECISION,

    calculated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_summary_country
        FOREIGN KEY (country_id)
        REFERENCES core.countries(country_id)
);