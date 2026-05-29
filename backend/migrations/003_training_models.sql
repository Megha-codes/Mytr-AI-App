-- Training samples table
CREATE TABLE training_samples (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID REFERENCES users(id),
    meal_log_id             UUID REFERENCES meal_logs(id),
    feature_vector          JSONB NOT NULL,
    recommended_dose        NUMERIC(5,2),
    actual_outcome          TEXT,           -- IN_RANGE / HIGH / LOW / HYPO / HYPER
    post_meal_glucose_2hr   INTEGER,
    label                   SMALLINT,       -- 1 = correct, 0 = incorrect
    created_at              TIMESTAMPTZ DEFAULT now()
);

-- Per-user trained models
CREATE TABLE user_models (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    model_bytes     BYTEA NOT NULL,         -- serialised XGBoost model
    accuracy        NUMERIC(4,3),
    sample_count    INTEGER,
    version         TEXT,
    trained_at      TIMESTAMPTZ DEFAULT now(),
    is_active       BOOLEAN DEFAULT true
);

-- Index for fast lookup of pending post-meal readings
CREATE INDEX idx_meal_logs_pending_1hr ON meal_logs (meal_time)
    WHERE post_meal_glucose_1hr IS NULL;

CREATE INDEX idx_meal_logs_pending_2hr ON meal_logs (meal_time)
    WHERE post_meal_glucose_2hr IS NULL;
