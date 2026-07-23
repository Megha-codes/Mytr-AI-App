-- mytr-desk device pipeline: pairing + reading store.
--
-- Serves the endpoints the desk device's syncd consumes:
--   WSS /v1/devices/stream, GET /v1/readings, POST /v1/devices/pair,
--   POST /v1/voice/query.
-- Lives in the main Postgres alongside users. The app also stands these tables
-- up programmatically at startup (init_device_schema), mirroring the Timescale
-- schema init; this file is the source-of-truth DDL for parity with the rest
-- of migrations/.

-- Paired desk devices. Auth is the device bearer token; only its SHA-256 hash
-- is stored (the raw token is shown to the device once, at claim time).
CREATE TABLE IF NOT EXISTS devices (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID REFERENCES users(id) ON DELETE CASCADE,
    token_hash   TEXT NOT NULL UNIQUE,
    name         TEXT,
    sensor_id    TEXT,
    paired_at    TIMESTAMP DEFAULT now(),
    last_seen_at TIMESTAMP,
    revoked_at   TIMESTAMP
);

-- Short-lived QR pairing handshakes. The device opens one and polls it; the
-- mobile app claims it by code. device_token holds the raw token transiently
-- between claim and the device's next poll, then is cleared.
CREATE TABLE IF NOT EXISTS pairing_sessions (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pairing_code TEXT NOT NULL UNIQUE,
    status       TEXT NOT NULL DEFAULT 'pending',  -- pending | claimed | consumed
    device_id    UUID REFERENCES devices(id) ON DELETE SET NULL,
    device_token TEXT,
    created_at   TIMESTAMP DEFAULT now(),
    expires_at   TIMESTAMP NOT NULL,
    claimed_at   TIMESTAMP
);

-- The reading store: exactly the shape syncd consumes. ts is unix epoch
-- seconds UTC (the poller resolves the Libre account timezone before writing);
-- trend is our string label (flat/rising/rising_rapid/falling/falling_rapid),
-- already translated from LibreLinkUp's 1-5 TrendArrow. Dedup key (sensor_id,
-- ts) lets the poller re-pull overlapping graph windows without duplicating.
CREATE TABLE IF NOT EXISTS device_readings (
    ts         BIGINT NOT NULL,
    mgdl       DOUBLE PRECISION NOT NULL,
    trend      TEXT,
    sensor_id  TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    PRIMARY KEY (sensor_id, ts)
);

-- Range scans by time dominate the backfill query (ts > since).
CREATE INDEX IF NOT EXISTS idx_device_readings_ts ON device_readings (ts);
