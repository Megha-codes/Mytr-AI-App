-- 011_glucose_dedup_and_region.sql
-- Architecture v3 §1.3 / §4.3 — shared Libre poller schema support.

-- glucose_readings lives in TimescaleDB; the equivalent DDL is also applied
-- on every boot by init_timescale_schema() (backend/app/timescale_database.py)
-- since that table isn't provisioned through this migration path. Keep both
-- in sync.
ALTER TABLE glucose_readings
  ADD COLUMN IF NOT EXISTS sensor_id TEXT,
  ADD COLUMN IF NOT EXISTS source    TEXT NOT NULL DEFAULT 'LIBRE';
    -- source ∈ 'LIBRE' | 'MANUAL' | 'ACCUCHEK'

-- Idempotent ingestion. The shared poller re-fetches overlapping graph windows
-- every cycle; without this it writes duplicates on every poll.
CREATE UNIQUE INDEX IF NOT EXISTS glucose_readings_dedup_idx
  ON glucose_readings (user_id, sensor_id, recorded_at)
  WHERE sensor_id IS NOT NULL;

-- Durable per-account region cache (§4.3 step 3) so a poller restart doesn't
-- re-scan all six regional LibreView hosts before its first successful poll.
-- Lives on cgm_devices (the user's CGM connection), not a new table — this is
-- exactly the record that already models "this user's Libre account".
ALTER TABLE cgm_devices
  ADD COLUMN IF NOT EXISTS region_base TEXT;
