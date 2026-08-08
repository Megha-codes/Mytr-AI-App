-- 013_health_metrics.sql
-- Architecture v3 §1.4 — replaces the daily-rollup-only `activity_logs`
-- design with a real time-series metric store. `activity_logs` stays as a
-- recomputed projection (§4.2), not an independently-written source.

CREATE TABLE IF NOT EXISTS health_metrics (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    metric        TEXT NOT NULL,  -- 'steps' | 'active_energy_kcal' | 'heart_rate'
                                  -- | 'resting_heart_rate' | 'hrv' | 'sleep_minutes' | 'weight_kg'
                                  -- (metric-agnostic column — not a CHECK-constrained enum)
    value         DOUBLE PRECISION NOT NULL,
    unit          TEXT NOT NULL,  -- 'count' | 'kcal' | 'bpm' | 'ms' | 'min' | 'kg'
    started_at    TIMESTAMPTZ NOT NULL,
    ended_at      TIMESTAMPTZ NOT NULL,  -- == started_at for instantaneous samples
    source        TEXT NOT NULL,  -- 'APPLE_HEALTH' | 'HEALTH_CONNECT' | 'FITBIT' | 'MANUAL'
    external_id   TEXT,           -- platform sample UUID, for idempotent re-sync
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS health_metrics_dedup_idx
  ON health_metrics (user_id, source, metric, external_id)
  WHERE external_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS health_metrics_lookup_idx
  ON health_metrics (user_id, metric, started_at DESC);
