# mytr-desk device pipeline — runbook

Backend endpoints the mytr-desk desk device consumes, matching the contract in
`mytr-desk` (`mockserver/server.py`, `docs/data-format.md`, `device/schema.sql`)
that syncd is already built against:

| Method | Path                     | Purpose                                            |
|--------|--------------------------|----------------------------------------------------|
| WSS    | `/v1/devices/stream`     | live readings (`{ts, mgdl, trend, sensor_id}`)     |
| GET    | `/v1/readings?since=<ts>`| backfill readings with `ts > since`                |
| POST   | `/v1/devices/pair`       | device opens a QR session, then polls for a token  |
| POST   | `/v1/devices/pair/claim` | mobile app (authed user) claims a pairing code     |
| POST   | `/v1/voice/query`        | Phase-4 stub — authed + routed, returns 501        |

Auth on stream / readings / voice is a **device bearer token** (only its
SHA-256 hash is stored). Readings carry UTC-epoch `ts` and the device trend
vocabulary (`flat/rising/rising_rapid/falling/falling_rapid`), translated from
LibreLinkUp's 1–5 `TrendArrow` and its US-style timezone-less timestamps by the
poller — never on the device.

The delivery guarantee: a stream connection `subscribe()`s before it's accepted,
so everything the poller publishes from acceptance onward is delivered in order.
syncd's stream-first-then-backfill ordering therefore has no gap.

---

## 1. Run the tests

```bash
cd backend
python -m venv .venv && . .venv/Scripts/activate   # or .venv/bin/activate on *nix
pip install -r requirements.txt -r requirements-dev.txt
python -m pytest -q
```

Covers the two highest-risk areas: the US-timestamp → UTC-epoch parsing
(`tests/test_libre_timestamp.py`) and the full pairing + device-auth flow
(`tests/test_pairing.py`).

## 2. Run the offline end-to-end proof

No Postgres, no Docker, no real credentials — a fake LibreLinkUp + the real
backend + syncd's real client code, all in one process:

```bash
cd backend
python -m proof.run_proof
```

It logs in to the fake LibreLinkUp (timestamps in `Asia/Kolkata`, i.e.
UTC+5:30), stores readings with correctly-parsed UTC epochs, streams them into
syncd, **forces a mid-stream disconnect**, and confirms syncd's backfill
recovers everything — **zero gaps, zero duplicates**, the same guarantee the
mock server gave. Exit code 0 on success.

Expected tail:

```
Results
-------
  [PASS] a forced mid-stream disconnect actually happened
  [PASS] readings were recovered via REST backfill - 6 backfilled
  [PASS] device captured the full set (no gaps) - 40/40
  [PASS] no duplicates on device
  [PASS] device set == backend set
  [PASS] timestamps parsed to correct UTC epochs
  [PASS] trend labels are device vocabulary - ...
PROOF PASSED
```

## 3. Run for real, with your LibreLinkUp credentials

### a. Configure

```bash
cd backend
cp config/.env.example .env        # .env is gitignored — safe for secrets
```

Fill in `.env`:

```
JWT_SECRET=<generate one>
LIBRE_EMAIL=<your LibreLinkUp email>
LIBRE_PASSWORD=<your LibreLinkUp password>
LIBRE_REGION=ap                    # your account's region (AP for us)
LIBRE_ACCOUNT_TIMEZONE=Asia/Kolkata # the account's IANA timezone
LIBRE_POLLER_ENABLED=true
# Offline store (skips Postgres); omit to use the main DATABASE_URL:
DEVICE_DATABASE_URL=sqlite+aiosqlite:///./mytr_device.db
```

Credentials live only in `.env` (gitignored) and are never logged.

### b. Start the backend + poller

Device pipeline only (no Postgres/Timescale needed):

```bash
uvicorn app.device_app:app --host 0.0.0.0 --port 8000
```

…or the full backend (needs Postgres + TimescaleDB, e.g. `docker compose up`,
and migrations `001`–`010` applied):

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Within ~60 s you should see `poll: N fetched, M new` in the logs — real Libre
readings landing in the store with UTC-epoch `ts`.

### c. Pair a device and point real syncd at it

1. Device: `POST /v1/devices/pair` → `{pairing_id, pairing_code}` (render the
   code as a QR).
2. Mobile app (authenticated user): `POST /v1/devices/pair/claim` with
   `{"pairing_code": "<code>"}`.
3. Device polls `POST /v1/devices/pair` with `{pairing_id}` → receives
   `device_token` once. Write it to the device's `token_path`.
4. In the `mytr-desk` repo, point `config/config.dev.yaml` `base_url` / `ws_url`
   at this backend and set `device.token_path` to the token file, then run
   syncd **on Linux/WSL2** (it uses a Unix-domain event socket, unavailable on
   native Windows):

   ```bash
   MYTR_CONFIG=./config/config.dev.yaml python -m device.syncd.main
   ```

   Force a disconnect (Ctrl-Z / kill the process, or drop the network) and watch
   it reconnect and backfill with no gaps — the same behaviour `proof/run_proof`
   demonstrates against syncd's client code here.

---

## Notes

- **Store location:** the pipeline uses dedicated `devices` / `pairing_sessions`
  / `device_readings` tables (`migrations/010_device_pairing_and_readings.sql`),
  kept isolated from the mobile `glucose_readings` path. `init_device_schema()`
  also stands them up programmatically on startup (mirroring the Timescale init),
  which is what lets the SQLite proof/tests run with no migration step.
- **`LIBRE_BASE_URL`** overrides the regional host (staging proxy / gateway);
  the proof uses it to point the real poller at the fake LibreLinkUp.
- **syncd on Windows:** `python -m proof.run_proof` exercises syncd's real
  `client`/`db`/`reading` modules against this backend. The full `device.syncd.main`
  additionally opens a Unix-domain event socket, so run *that* under Linux/WSL2.
