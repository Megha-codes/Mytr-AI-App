-- Activity sync table — one row per user per day, upserted from the phone
CREATE TABLE IF NOT EXISTS activity_logs (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date        DATE NOT NULL DEFAULT CURRENT_DATE,
    steps_today INTEGER NOT NULL DEFAULT 0,
    calories_burned INTEGER NOT NULL DEFAULT 0,
    heart_rate  INTEGER NOT NULL DEFAULT 0,
    synced_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enforce one row per user per day; upsert targets this index
CREATE UNIQUE INDEX IF NOT EXISTS activity_logs_user_date_idx
    ON activity_logs (user_id, date);
