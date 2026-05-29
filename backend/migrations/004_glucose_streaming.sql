CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Add new columns to existing cgm_devices table
ALTER TABLE cgm_devices
ADD COLUMN IF NOT EXISTS is_continuous BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS supports_trend BOOLEAN DEFAULT false;

-- Create glucose readings table
CREATE TABLE IF NOT EXISTS glucose_readings (
    id              UUID DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL, -- references users(id) in practice
    recorded_at     TIMESTAMPTZ NOT NULL,
    value_mgdl      INTEGER NOT NULL,
    trend           TEXT,
    trend_arrow     TEXT,
    device_type     TEXT NOT NULL,
    is_continuous   BOOLEAN DEFAULT false,
    created_at      TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (id, recorded_at)
);

-- Convert to TimescaleDB hypertable
SELECT create_hypertable('glucose_readings', 'recorded_at', if_not_exists => TRUE);

-- Index for fast latest reading queries
CREATE INDEX IF NOT EXISTS idx_glucose_readings_user_recorded 
ON glucose_readings (user_id, recorded_at DESC);

-- Create a continuous aggregate for daily summaries
CREATE MATERIALIZED VIEW IF NOT EXISTS glucose_daily_summary
WITH (timescaledb.continuous) AS
SELECT
    user_id,
    time_bucket('1 day', recorded_at) AS bucket,
    MIN(value_mgdl) AS min_glucose,
    MAX(value_mgdl) AS max_glucose,
    AVG(value_mgdl) AS avg_glucose,
    COUNT(value_mgdl) AS reading_count
FROM glucose_readings
GROUP BY user_id, bucket
WITH NO DATA;

-- Since the user didn't specify a refresh policy, we can add a basic default one
SELECT add_continuous_aggregate_policy('glucose_daily_summary',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');
