-- 010_architecture_v3_auth.sql
-- Architecture v3 §1.1 / §1.2 — device auth foundation.
--
-- Per-user timezone (retires the global LIBRE_ACCOUNT_TIMEZONE setting for
-- the shared poller, built in a later pass) and the desk-device pairing
-- tables. `devices` is deliberately separate from `cgm_devices`: the latter
-- models a user's CGM sensor connection, this models a physical desk unit.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'UTC';

CREATE TABLE IF NOT EXISTS devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES users(id) ON DELETE CASCADE,  -- NULL until paired
    hardware_id         TEXT NOT NULL UNIQUE,   -- Pi serial from /proc/cpuinfo
    kind                TEXT NOT NULL DEFAULT 'DESK',
    name                TEXT,                   -- user-editable, "Bedside"
    firmware_version    TEXT,
    token_version       INTEGER NOT NULL DEFAULT 0,  -- bump to revoke this device
    paired_at           TIMESTAMPTZ,
    last_seen_at        TIMESTAMPTZ,
    revoked_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS devices_user_idx ON devices (user_id) WHERE revoked_at IS NULL;

-- Short-lived pairing codes. Device-initiated: the device generates nothing
-- secret, the backend does.
CREATE TABLE IF NOT EXISTS device_pairing_codes (
    code            TEXT PRIMARY KEY,          -- 8 chars, Crockford base32, no vowels
    hardware_id     TEXT NOT NULL,
    device_id       UUID REFERENCES devices(id) ON DELETE CASCADE,
    claimed_by      UUID REFERENCES users(id) ON DELETE CASCADE,
    expires_at      TIMESTAMPTZ NOT NULL,      -- now() + 10 minutes
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS device_pairing_codes_expiry_idx ON device_pairing_codes (expires_at);
