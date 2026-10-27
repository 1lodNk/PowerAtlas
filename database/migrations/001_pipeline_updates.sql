-- Migration — prepare core layer for the raw -> core pipeline

-- 1. Link every core plant back to the raw row it came from

ALTER TABLE core.plants
    ADD COLUMN IF NOT EXISTS source_raw_id BIGINT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_plants_source_raw_id
    ON core.plants (source_raw_id);


-- 2. Storage plants consume more energy than they produce, so net generation is legitimately negative. Keep those values.

ALTER TABLE core.generation
    DROP CONSTRAINT IF EXISTS chk_actual_generation;


-- 3. Data quality findings (rebuilt on every pipeline run)
CREATE TABLE IF NOT EXISTS core.data_quality_issues (
    issue_id    BIGSERIAL PRIMARY KEY,
    rule        VARCHAR(100) NOT NULL,
    severity    VARCHAR(20)  NOT NULL,
    raw_id      BIGINT,
    plant_id    BIGINT,
    detail      TEXT,
    detected_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_dq_severity
        CHECK (severity IN ('info', 'warning', 'error'))
);

CREATE INDEX IF NOT EXISTS idx_dq_rule ON core.data_quality_issues (rule);
