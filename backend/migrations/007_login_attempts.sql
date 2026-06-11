-- Persistent login-attempt log backing per-account lockout.
CREATE TABLE IF NOT EXISTS login_attempts (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email      TEXT NOT NULL,
    ip         TEXT,
    successful BOOLEAN NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

-- Lockout queries filter by email + recent time window.
CREATE INDEX IF NOT EXISTS idx_login_attempts_email_time
    ON login_attempts (email, created_at);
