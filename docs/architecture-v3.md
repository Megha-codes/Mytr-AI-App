# Architecture v3 — app as hub, backend as source of truth, device as display

Status: **settled design, not yet built.** This document is the contract three
people can build against in parallel (app / backend / device). No deadline is
implied; the ordering constraints at the end are correctness constraints, not
schedule.

Supersedes:

- The standalone-device architecture in `mytr-desk/CLAUDE.md` ("Fully standalone
  product… no user accounts, no pairing, no cloud sync… device pulls glucose
  directly from Abbott LibreLinkUp").
- `device-repo-export/MANIFEST.md`, which exported `libre_poller.py` into the
  desk repo for that standalone design.

Builds on:

- `backend/docs/consolidation-plan.md` (deleted from the working tree; readable
  at `git show baaf023:backend/docs/consolidation-plan.md`). Its **"one poller,
  two sinks"** design is now simply **the backend's shared poller**. Sink A
  (mobile) and Sink B (device) both become *readers of the backend store* rather
  than two ingestion paths — see §4.3.

---

## 0. The shape, in one picture

```
  Abbott LibreLinkUp                Apple Health / Google Health Connect
          │                                      │
          │ (backend polls, per-user creds)      │ (app reads, app pushes)
          ▼                                      ▼
  ┌───────────────────────────────────────────────────────────────┐
  │                       mytr.ai backend                          │
  │  LibreIngestionService (one loop per distinct Libre account)   │
  │  Postgres: users, devices, health_metrics, meal_logs           │
  │  TimescaleDB: glucose_readings                                 │
  │  Fanout hub: publishes to every live subscriber of a user_id   │
  └──────────┬──────────────────────────────────┬─────────────────┘
             │ user JWT                          │ device JWT
             ▼                                   ▼
      ┌─────────────┐                    ┌──────────────────┐
      │ mytr.ai app │  ← THE HUB         │   desk device    │  ← display only
      │ login       │                    │ no Libre creds   │
      │ Libre creds │                    │ no direct polling│
      │ Health perms│                    │ local alarms off │
      │ meal entry  │                    │ cached readings  │
      └─────────────┘                    └──────────────────┘
```

One rule decides every ambiguous case: **credentials and permissions live where
a human can grant them (the app); data lives in the backend; the device only
reads.**

### Safety carve-out that survives the reset

`mytr-desk/CLAUDE.md` constraint #1 said alarms must never depend on our
servers. That constraint **stays**, in a weaker but still hard form:

- Alarm evaluation remains **local to the device**, against the device's own
  SQLite cache (`device/alarmd/*`, `device/schema.sql`). It is unchanged.
- What changes is only where the cache is *filled from*: the backend stream
  instead of Abbott directly.
- A device that loses backend connectivity must keep alarming on its cached
  readings and raise the existing `stale_data` rule (no reading for 15 min).
  It must **never** display or alarm on a synthesized value. This is the same
  no-fake-readings rule already enforced backend-side in
  `backend/app/services/cgm/libre_service.py` (commit f6883d8).

---

## 1. Data model (settled)

Two stores, as today: **Postgres** (`backend/app/database.py`) for relational
data, **TimescaleDB** (`backend/app/timescale_database.py`) for glucose
time-series. Migrations continue the numbered sequence in
`backend/migrations/` — next free number is **010**.

### 1.1 `users` — exists, one column added

`backend/app/models/user.py:8`, `migrations/001_initial_schema.sql`.

Unchanged: `id`, `email`, `password_hash`, `email_verified`, `name`, `dob`,
`gender`, `weight_kg`, `height_cm`, `diabetes_type`, `consent_confirmed_at`,
`terms_accepted_at`, `token_version`.

**Add:**

```sql
-- 010_architecture_v3.sql
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'UTC';
```

Why: the consolidation plan flagged that the mobile path resolves LibreLinkUp's
naive timestamps against the single `LIBRE_ACCOUNT_TIMEZONE` setting
(`backend/app/core/config.py:17`) rather than per user. With one shared backend
poller serving many accounts, a global setting is no longer merely imprecise —
it is wrong for every user outside that zone. The app writes this at onboarding
from the device locale and on every profile save.

### 1.2 `devices` — new (desk devices; distinct from `cgm_devices`)

`cgm_devices` (`backend/app/models/user.py:53`) stays exactly as it is: it
models *the user's CGM sensor connection*. The desk unit is a different thing
and gets its own table. Do not overload one for the other.

```sql
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
```

A user may have many devices. A device is bound to exactly one user; re-pairing
to a different user requires an explicit unpair (which bumps `token_version`).

### 1.3 `glucose_readings` — exists, two columns added

TimescaleDB hypertable, `migrations/004_glucose_streaming.sql`, model at
`backend/app/models/glucose_reading.py`.

Existing: `id`, `user_id`, `recorded_at TIMESTAMPTZ`, `value_mgdl`, `trend`,
`trend_arrow`, `device_type`, `is_continuous`, `created_at`.

**Add:**

```sql
ALTER TABLE glucose_readings
  ADD COLUMN IF NOT EXISTS sensor_id TEXT,
  ADD COLUMN IF NOT EXISTS source    TEXT NOT NULL DEFAULT 'LIBRE';
    -- source ∈ 'LIBRE' | 'MANUAL' | 'ACCUCHEK'

-- Idempotent ingestion. The shared poller re-fetches overlapping graph windows
-- every cycle; without this it writes duplicates on every poll.
CREATE UNIQUE INDEX IF NOT EXISTS glucose_readings_dedup_idx
  ON glucose_readings (user_id, sensor_id, recorded_at)
  WHERE sensor_id IS NOT NULL;
```

Ingestion becomes `INSERT … ON CONFLICT DO NOTHING` against that index. This is
the same dedup the device already does locally on `(ts, sensor_id)`
(`mytr-desk/device/schema.sql`), moved server-side.

`trend` uses the device's five string labels — `flat`, `rising`, `rising_rapid`,
`falling`, `falling_rapid` — produced by `map_trend_arrow`. `trend_arrow` stays
the display glyph. Do not put LibreLinkUp's raw integer 1–5 in either.

**Units:** mg/dL everywhere internally, integer. mmol/L is display-layer only,
on both app and device.

### 1.4 `health_metrics` — new (replaces the daily-rollup-only design)

Today the only health storage is `activity_logs`
(`migrations/009_activity_sync.sql`): one row per user per day holding
`steps_today`, `calories_burned`, `heart_rate`, last-write-wins. That is a
display cache, not a data model — it cannot answer "heart rate at 14:30", can't
merge two sources, and silently loses history.

```sql
CREATE TABLE IF NOT EXISTS health_metrics (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    metric        TEXT NOT NULL,  -- 'steps' | 'active_energy_kcal' | 'heart_rate'
                                  -- | 'resting_heart_rate' | 'sleep_minutes' | 'weight_kg'
    value         DOUBLE PRECISION NOT NULL,
    unit          TEXT NOT NULL,  -- 'count' | 'kcal' | 'bpm' | 'min' | 'kg'
    started_at    TIMESTAMPTZ NOT NULL,
    ended_at      TIMESTAMPTZ NOT NULL,  -- == started_at for instantaneous samples
    source        TEXT NOT NULL,  -- 'APPLE_HEALTH' | 'GOOGLE_HEALTH_CONNECT' | 'FITBIT' | 'GARMIN' | 'MANUAL'
    external_id   TEXT,           -- platform sample UUID, for idempotent re-sync
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS health_metrics_dedup_idx
  ON health_metrics (user_id, source, metric, external_id)
  WHERE external_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS health_metrics_lookup_idx
  ON health_metrics (user_id, metric, started_at DESC);
```

`activity_logs` **stays** as a derived daily rollup — `POST /activity/sync`
continues to work unchanged so the current app build doesn't break — but it
becomes a *projection* the backend recomputes from `health_metrics`, not an
independently-written source. See §4.2 for the cutover.

Idempotency note: Apple Health and Health Connect both expose stable per-sample
identifiers; the app must send them as `external_id`. Where a platform doesn't
(aggregated step buckets), the app sends `external_id = "{metric}:{bucket_start_iso}"`
so a re-sync overwrites rather than double-counts.

### 1.5 `meal_logs` (calorie entries) — exists, unchanged

`migrations/002_meal_logs.sql` + `005_add_fiber_to_meal_logs.sql`, model at
`backend/app/models/meal_log.py`. Already carries `meal_time`, `food_items`
(JSONB), `total_calories`, `total_carbs_g`, `total_protein_g`, `total_fat_g`,
`total_fiber_g`, `glycaemic_load`, plus post-meal glucose outcome fields.

No schema change needed. What's missing is *read* access (§2.5) — everything
written there today is write-only from the API's perspective, surfaced solely
through `GET /api/v1/dashboard`.

### 1.6 Libre credentials — unchanged location, new consumer

Per-user LibreLinkUp credentials stay in the secrets manager, written at connect
time by `backend/app/api/cgm_connect.py:70` via
`secrets_manager.store_libre_credentials`, encrypted with
`backend/app/core/encryption.py`. The device never sees them and no endpoint
ever returns them.

> `backend/app/core/secrets_manager.py` is `MockSecretsManager` — an in-process
> dict. It is adequate for dev and **not** adequate for a shared poller holding
> many users' Abbott credentials across restarts. Swapping in a real backing
> store (AWS Secrets Manager / Vault) is a prerequisite for §4.3, listed in the
> audit as a gap.

---

## 2. API contract

Base: `/api/v1` for the existing app surface (unchanged prefixes registered in
`backend/app/main.py:40-54`). Device routes live under `/api/v1/device` and
`/ws/device`.

### 2.1 Two token audiences

| | user token | device token |
|---|---|---|
| issued by | `POST /api/v1/auth/login` | `POST /api/v1/device/pair/poll` (on claim) |
| JWT `type` claim | `access` / `refresh` | `device_access` / `device_refresh` |
| subject `sub` | `user_id` | `device_id` |
| extra claims | `tv` = `users.token_version` | `uid` = user_id, `tv` = `devices.token_version` |
| access lifetime | 24h (`ACCESS_TOKEN_EXPIRE_MINUTES`) | **1h** |
| refresh lifetime | 7d / 30d remember-me | **90d**, rotated on use |
| scope | full app API | read-only device endpoints in §2.4 only |

The `type`-claim discrimination already exists in
`backend/app/core/security.py` (`TOKEN_TYPE_ACCESS`, `…_REFRESH`, `…_RESET`,
`…_VERIFY`) and `decode_token_payload` rejects cross-type use. Add
`TOKEN_TYPE_DEVICE_ACCESS` / `TOKEN_TYPE_DEVICE_REFRESH` there — do not reuse
the user types, or a stolen device token becomes a full account token.

Add a `get_current_device()` dependency mirroring `get_current_user`
(`backend/app/api/auth.py`), which resolves `devices` by `sub`, rejects
`revoked_at IS NOT NULL`, checks `tv` against `devices.token_version`, and
returns `(device, user_id)`.

Revocation: unpairing or "sign out device" bumps `devices.token_version`; the
user's global `logout-all` (`POST /api/v1/auth/logout-all`) bumps
`users.token_version` and **also** every owned device's `token_version`.

### 2.2 Pairing (device ⇄ app ⇄ backend)

No LibreLinkUp credentials, no email, no password are ever typed on the device.
The desk unit has a touchscreen but no comfortable keyboard, and typing an
account password on a shared-surface display is the wrong trust model.

```
device                         backend                          app
  │  POST /device/pair/start      │                              │
  │─────────────────────────────▶ │  create devices row (user_id NULL)
  │  {hardware_id, firmware}      │  + device_pairing_codes row
  │ ◀───────────────────────────  │
  │  {code:"K7M2-QP94", expires_in:600}
  │                               │
  │  [displays code on screen]    │        user reads code, types in app
  │                               │  POST /devices/pair  {code}  │
  │                               │ ◀────────────────────────────│  (user JWT)
  │                               │  bind devices.user_id, set paired_at
  │                               │ ────────────────────────────▶│ {device_id, name}
  │  POST /device/pair/poll       │                              │
  │  {hardware_id, code}          │  (long-poll, ≤30s, 200 when claimed)
  │ ◀───────────────────────────  │
  │  {device_access_token, device_refresh_token, user_id, expires_in}
```

| Method | Path | Auth | Body / Result |
|---|---|---|---|
| `POST` | `/api/v1/device/pair/start` | none (rate-limited by `hardware_id` + IP, 5/hr) | `{hardware_id, firmware_version}` → `{code, expires_in}` |
| `POST` | `/api/v1/device/pair/poll` | none | `{hardware_id, code}` → `202 {status:"pending"}` or `200 {device_access_token, device_refresh_token, user_id, device_name, expires_in}`. Long-polls up to 30s. Code is single-use and deleted on success. |
| `POST` | `/api/v1/devices/pair` | user JWT | `{code, name?}` → `{device_id, name, paired_at}`. `404` unknown/expired code, `409` already claimed. |
| `GET` | `/api/v1/devices` | user JWT | `[{device_id, name, kind, last_seen_at, firmware_version, paired_at}]` |
| `PATCH` | `/api/v1/devices/{device_id}` | user JWT | `{name}` |
| `DELETE` | `/api/v1/devices/{device_id}` | user JWT | unpair: `revoked_at = now()`, `token_version += 1`. Device's next call gets `401` and it returns to the pairing screen. |
| `POST` | `/api/v1/device/token/refresh` | device refresh token | → new access + rotated refresh |

Codes: 8 chars from Crockford base32 minus vowels (no accidental words, no
0/O·1/I confusion), grouped `XXXX-XXXX` for reading aloud. 10-minute TTL. Poll
attempts against a wrong code are rate-limited per `hardware_id` at 10/min.

### 2.3 What the device sends up

Exactly two things, both optional to the data path:

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/v1/device/heartbeat` | device JWT | `{firmware_version, uptime_s, last_reading_ts, alarm_state}` → `{}`. Updates `devices.last_seen_at`. Every 5 min. |
| `POST` | `/api/v1/voice/query` | device JWT | Unchanged in spirit from `mytr-desk/backend/app.py`, but auth moves from the shared `X-Device-Key` header to the per-device JWT, and `glucose_context` is no longer sent by the device — the backend already has the user's readings and injects them itself. |

The device is **not** a writer of glucose, health, or calorie data. There is no
device→backend ingestion endpoint. If a future device gains a sensor, it gets a
new endpoint and a new §, not a widening of these.

### 2.4 What the device fetches

All device endpoints are **read-only**, scoped implicitly to the paired user
(`uid` claim). None of them take a `user_id` parameter — the token decides.

```
GET /api/v1/device/snapshot
```
The boot / reconnect call. One round trip to fill a cold screen.
```jsonc
{
  "server_time":  "2026-07-28T09:14:03Z",
  "user":    { "name": "Asha", "timezone": "Asia/Kolkata",
               "target_low": 70, "target_high": 180 },
  "glucose": { "latest": { "ts": 1753693200, "mgdl": 132, "trend": "flat",
                           "sensor_id": "a1b2c3", "source": "LIBRE" },
               "readings": [ /* last 24h, ascending, same shape */ ],
               "state": "LIVE" },        // LIVE | STALE | NO_SENSOR | NOT_CONNECTED
  "health":  { "date": "2026-07-28", "steps": 4210,
               "active_energy_kcal": 318, "heart_rate": 72,
               "updated_at": "2026-07-28T09:02:11Z" },
  "calories":{ "date": "2026-07-28", "consumed_kcal": 1240, "carbs_g": 143.5,
               "protein_g": 61.0, "fat_g": 44.2, "fiber_g": 18.0,
               "meals": [ { "id": "...", "meal_time": "2026-07-28T08:10:00Z",
                            "label": "Poha", "calories": 320, "carbs_g": 48.0 } ] }
}
```

| Method | Path | Query | Returns |
|---|---|---|---|
| `GET` | `/api/v1/device/snapshot` | — | the object above |
| `GET` | `/api/v1/device/glucose/latest` | — | `{ts, mgdl, trend, trend_arrow, sensor_id, source, state}` |
| `GET` | `/api/v1/device/glucose/range` | `from` (epoch s, required), `to` (epoch s, default now), `max_points` (default 720) | `{readings:[…], truncated: bool}` — ascending by `ts`. Backs the 3h/6h/24h graphs. |
| `GET` | `/api/v1/device/health/daily` | `date` (ISO date, default today in user tz) | `{date, steps, active_energy_kcal, heart_rate, resting_heart_rate, sleep_minutes, updated_at}`; fields absent when unsynced — **never zero-filled** (0 steps and "no data" are different facts) |
| `GET` | `/api/v1/device/calories/daily` | `date` | `{date, consumed_kcal, carbs_g, protein_g, fat_g, fiber_g, meals:[…]}` |

Errors: `401` expired/revoked token (device refreshes, then re-pairs on a second
`401`), `404` no data for the requested date, `429` with `Retry-After`.

Caching: every GET returns `ETag`; the device sends `If-None-Match` and handles
`304`. This matters on a Pi Zero 2 W with a metered link.

**`state` is load-bearing.** The device renders a distinct screen per value and
must never substitute a number:

| `state` | meaning | device shows |
|---|---|---|
| `LIVE` | reading < 10 min old | value + trend + graph |
| `STALE` | newest reading ≥ 10 min old | last value greyed + "as of HH:MM" + stale banner; `alarmd` stale rule owns the tone |
| `NO_SENSOR` | Libre connected, sensor expired/absent | "No sensor" |
| `NOT_CONNECTED` | user has no active CGM connection in the app | "Connect a CGM in the mytr.ai app" |

### 2.5 App-facing endpoints that must be added

These are gaps the app needs regardless of the device (see audit §5):

| Method | Path | Why |
|---|---|---|
| `POST` | `/api/v1/health/samples` | batch push of `health_metrics` rows: `{samples:[{metric, value, unit, started_at, ended_at, source, external_id}]}` → `{accepted, duplicates}`. Max 1000/request. Replaces the lossy `POST /activity/sync`. |
| `GET` | `/api/v1/health/daily` | user-JWT twin of the device endpoint |
| `GET` | `/api/v1/nutrition/meals` | `?from&to` — list meals. Today `meal_logs` is write-only over the API. |
| `DELETE` | `/api/v1/nutrition/meals/{id}` | correct a mis-logged meal |
| `GET` | `/api/v1/nutrition/daily` | daily calorie/macro totals |
| `GET` | `/api/v1/glucose/range` | user-JWT twin of the device range endpoint |

### 2.6 Realtime

**One mechanism, two audiences: a WebSocket carrying a versioned envelope.**

```
WS /ws/device/stream        Sec-WebSocket-Protocol: bearer, <device_access_token>
WS /ws/app/stream           Sec-WebSocket-Protocol: bearer, <user_access_token>
```

Both are served by the same fanout hub keyed on `user_id`; they differ only in
which token type authenticates and (for the app) that it may receive
device-status events. The token goes in the `Sec-WebSocket-Protocol` header, not
the query string — query strings land in access logs.

Envelope, every frame:

```jsonc
{ "v": 1, "type": "glucose.reading", "ts": 1753693200, "seq": 4412, "data": { … } }
```

| `type` | `data` | emitted when |
|---|---|---|
| `hello` | `{server_time, seq, heartbeat_s: 30}` | on connect, first frame |
| `glucose.reading` | `{ts, mgdl, trend, trend_arrow, sensor_id, source}` | poller ingests a new reading |
| `glucose.state` | `{state, since}` | state transitions (§2.4) |
| `health.updated` | `{date}` | app pushes health samples; consumer re-GETs `/health/daily` |
| `calories.updated` | `{date}` | meal logged/deleted; consumer re-GETs `/calories/daily` |
| `device.command` | `{command}` — `refresh` \| `identify` \| `reboot` | user acts in the app |
| `ping` | `{}` | every 30s |

`seq` is a per-user monotonic counter. On reconnect the client sends
`{"type":"resume","since_seq":N}` as its first frame; the hub replays missed
`glucose.reading` frames from the store (bounded to 24h) or answers
`{"type":"resync"}` telling the client to re-fetch `/snapshot`. This is what
makes a flaky Pi link recoverable without a fake-data window.

`health.updated` and `calories.updated` deliberately carry **no payload** — they
are cache-invalidation signals. Only glucose, which is latency-sensitive and
tiny, is pushed inline.

Fallback: if a WebSocket cannot be established (captive portal, proxy), the
device degrades to polling `/device/glucose/latest` every 60s. Same data, worse
latency, no code path difference in the renderer.

Reconnect: exponential backoff with jitter, 1s → 60s cap. The device's existing
`device/libred/backoff.py` is the right module to keep for this.

---

## 3. Three-way split of responsibilities

### 3.1 The app provides

| Capability | Detail |
|---|---|
| Identity | The only place an account is created (`POST /api/v1/users/onboard`) and the only place a password is typed. |
| LibreLinkUp credentials | Collected once in `libre_connect_screen.dart`, posted to `/cgm/connect/libre`, never stored on the phone, never shown again. |
| Apple Health / Health Connect | Holds the OS permission grants; reads samples; batches them to `POST /api/v1/health/samples`. **This is the app's exclusive job** — neither backend nor device can reach these APIs. |
| Calorie entry | Photo recognition, food search, portion entry, corrections. |
| Device management | Pairing (typing the code), naming, unpairing, seeing `last_seen_at`. |
| Profile & targets | Timezone, target glucose range, insulin profile. |

Background health sync: iOS gets `HKObserverQuery` + background delivery,
Android gets a periodic WorkManager job. Both post to `/health/samples`. If the
app is never opened, health data simply stops arriving — the device must render
that as absent data, not zeros. Glucose is unaffected because the *backend*
polls it.

### 3.2 The backend provides

| Capability | Detail |
|---|---|
| Shared Libre poller | `LibreIngestionService`: one loop per distinct Libre account, deduped by credentials, running 24/7 independent of any client connection. This is the consolidation plan's poller, now with exactly one sink (the store) and a fanout hub on top. |
| Account registry | Which accounts to poll = every user with stored Libre credentials **and** an active `cgm_devices` row. A user with no live app session and no device is still polled. |
| Per-user timezone resolution | `users.timezone` → `libre_timestamp_to_epoch` (`backend/app/services/libre_timestamp.py`). Retires `LIBRE_ACCOUNT_TIMEZONE`. |
| Storage | Postgres + TimescaleDB, per §1. Sole source of truth. |
| Fanout | One hub, `user_id` → set of subscribers (app sockets + device sockets), with `seq` and replay. |
| Aggregation | Daily health/calorie rollups, time-in-range, the existing `/dashboard`. |
| Voice proxy | Moves here from `mytr-desk/backend/`, gaining real auth and server-side glucose context. |
| Rate-limit hygiene | Single-flight per Abbott account, 429 backoff with jitter, circuit breaker that surfaces `STALE` — **never** a synthesized reading. |

### 3.3 The device consumes

| Capability | Detail |
|---|---|
| Pairing UI | Shows the code, polls for the claim, stores the returned tokens. Replaces the first-boot credentials screen. |
| Sync daemon (`syncd`) | Replaces `libred`. Holds the device tokens, opens the stream, writes readings to the same local SQLite (`device/schema.sql`), publishes the same `new_reading` events on `/run/mytr/events.sock`. **`alarmd` requires zero changes.** |
| Alarms | Unchanged. Local, offline-capable, `device/alarmd/rules.py` and its test suite intact. |
| Display | Glucose value/trend/graph/TIR as today, plus new health and calorie panels fed by `/device/health/daily` and `/device/calories/daily`. |
| Voice | `voiced` sends audio + device JWT; stops assembling `glucose_context`. |

The device holds: its two tokens (encrypted at rest in `/var/lib/mytr`, the slot
`device/libred/credentials.py` currently uses for Libre creds), its cached
readings, its alarm config. Nothing else. It never holds an account password or
a Libre credential.

---

## 4. Migration notes

### 4.1 Device side: `libred` → `syncd`

| Component | Fate |
|---|---|
| `device/libred/libre_poller.py` | **Removed.** Its logic — LibreLinkUp client, region scan, token cache, `parse_libre_timestamp`, `map_trend_arrow`, `normalize_reading` — moves into the backend's `LibreIngestionService`. This retires the INTENTIONAL DUPLICATE banner and the two-repo fix obligation that `device-repo-export/MANIFEST.md` and `mytr-desk/CLAUDE.md` both warn about. **One copy, backend-side, `backend/app/services/libre_timestamp.py`.** |
| `device/libred/credentials.py` | **Repurposed.** Same encrypted local store, now holding device tokens instead of Libre email/password. Existing stored Libre credentials must be **deleted** on upgrade, not migrated. |
| `device/libred/db.py` | **Kept.** Same `readings` table, same `(ts, sensor_id)` dedup, same writer role — new upstream. |
| `device/libred/events.py` | **Kept verbatim.** The `new_reading` socket contract is what decouples `alarmd` from the data source. |
| `device/libred/backoff.py` | **Kept**, now governing stream reconnect instead of Abbott polling. |
| `device/libred/reading.py` | **Kept.** `parse_reading` already validates exactly the `{ts, mgdl, trend, sensor_id}` shape the stream sends. Extend for `source`. |
| `device/libred/main.py`, `config.py` | **Rewritten** as `syncd`: connect stream, fetch snapshot, write, publish. Config gains `backend.base_url`; loses everything under `librelinkup.`. |
| `device/alarmd/**` | **Untouched**, tests and all. |
| `device/ui/` first-boot credentials screen | **Replaced** by the pairing-code screen. |
| `device/ui/` main screen | **Extended** with health + calorie panels. |
| `mockserver/` (fake LibreLinkUp) | **Retargeted** to a fake *mytr.ai backend* — stream + the five device GETs. The `--drop-every`/`--fail-every` fault injection is worth preserving verbatim against the new surface. |
| `cgm-pipeline/` submodule | **Kept read-only** as the LibreLinkUp format reference until the backend client is verified against a real account, then detachable. |
| `deploy/libred.service` | Renamed `syncd.service`; `alarmd.service`, `mytr-ui.service`, `install.sh`, tmpfiles config unchanged. |
| `mytr-desk/backend/` (voice proxy) | **Moved** into this repo. `X-Device-Key` shared-secret auth is deleted in favour of per-device JWTs. |
| `device-repo-export/` | **Deleted.** Its entire premise (export the poller to a standalone device) is reversed. |

### 4.2 Backend: health data

1. Ship `health_metrics` + `POST /api/v1/health/samples`.
2. Ship the app change that writes samples; keep `POST /activity/sync` working
   for older installs.
3. `activity_logs` becomes a recomputed projection: on sample ingest, upsert the
   day's rollup. `/api/v1/dashboard` (`backend/app/api/dashboard.py:32`) and
   `activity_provider.dart` keep reading it and need no change.
4. Retire `POST /activity/sync` only once client telemetry shows no old builds
   calling it.

### 4.3 Backend: the shared poller (the consolidation plan, executed)

The plan's steps 1–7 stand, with its Sink A/Sink B split collapsed — there is
now one sink (the store) plus a fanout hub, because the device reads from the
store rather than having its own tables.

1. ~~Extract `libre_timestamp.py`~~ — **done** (`backend/app/services/libre_timestamp.py`, commit f6883d8).
2. Build `LibreIngestionService`: fold `libre_service.py`'s HTTP logic together
   with the exported `libre_poller.py` mechanics. Correct headers (`version
   4.16.0` plus `accept-encoding`/`cache-control`/`connection`, per
   `mytr-desk/docs/data-format.md`) — `libre_service.py`'s `_LLU_HEADERS` still
   says `4.7.0` and is missing them; the poller copy is right.
3. Account registry + per-user timezone (§1.1). Durable per-account region
   persistence so the first poll after restart doesn't re-scan six regional
   hosts.
4. Ingestion writes `glucose_readings` with `ON CONFLICT DO NOTHING` (§1.3) and
   publishes to the hub.
5. Convert `/ws/glucose/{user_id}` from poller to hub subscriber. **Delete
   `_start_polling_loop`** (`backend/app/api/websockets/glucose_stream.py:177`)
   — the live card stops depending on a foregrounded app.
6. Point `/ws/device/stream` at the same hub.
7. Replace `MockSecretsManager` with a durable encrypted store.
8. Load-test one real account: exactly one login + one query stream, no
   rate-limit trips.

The plan's original rationale gets *stronger* here: previously two loops raced
on one Abbott account; under v3 a user with a phone and two desk devices would
have had three. One backend loop per account is the only shape that scales.

### 4.4 Sequencing (correctness order, not schedule)

Parallel from day one: **(A)** backend §4.3 + §2.5, **(B)** app §2.5 clients +
pairing UI + health batching, **(C)** device `syncd` + pairing screen against
the retargeted `mockserver`.

Hard ordering constraints:

- Device tokens (§2.1–2.2) must exist before any `/device/*` endpoint is
  reachable. Build them first, backend-side.
- The stream contract (§2.6) must be frozen before (C) starts, since the mock
  server is written against it.
- No device ships to a real user before §4.3 step 4 — until ingestion is
  independent of client connections, a device shows data only while the phone
  app happens to be open.
- The old Libre credentials on any test device must be wiped during the
  `libred`→`syncd` upgrade, not left dormant.

---

## 5. Audit: what already exists

Verified against the tree at commit `f6883d8` (`fix/libre-service-safety`).

### 5.1 User accounts / auth

| Item | Status | Where |
|---|---|---|
| Signup / onboarding | **exists** | `backend/app/api/onboarding.py:25`, `frontend/lib/features/onboarding/ui/screens/*` |
| Login, JWT access+refresh | **exists** | `backend/app/api/auth.py:175`, `:148`; `backend/app/core/security.py` |
| Token type discrimination | **exists** | `security.py` `TOKEN_TYPE_*` + `decode_token_payload` |
| Token revocation (`token_version` / `tv`) | **exists** | `models/user.py:27`, `auth.py:337` (`logout-all`) |
| Account lockout, per-email persistent | **exists** | `auth.py:38-68`, `migrations/007_login_attempts.sql` |
| Email verification, password reset | **exists** | `auth.py:251-336`, `migrations/006_email_verification.sql` |
| Change password / email / delete account | **exists** | `backend/app/api/account.py` |
| App-side auth (login, storage, session) | **exists** | `frontend/lib/features/auth/**`, `core/services/auth_storage_service.dart`, `core/auth/auth_session_provider.dart` |
| `get_current_user` dependency | **exists** | `backend/app/api/auth.py` (Bearer header) |
| **Per-user timezone** | **missing** | needed by §1.1; `LIBRE_ACCOUNT_TIMEZONE` is global (`core/config.py:17`) |
| **Device accounts / `devices` table** | **missing** | nothing; prior device work exists only as orphaned `.pyc` (`app/core/__pycache__/device_auth.cpython-313.pyc`, `app/api/__pycache__/devices.cpython-313.pyc`) — the sources were deleted |
| **Pairing flow** | **missing** | — |
| **`get_current_device` dependency** | **missing** | — |

> ⚠️ Two auth defects to fix while building this, both pre-existing:
> **(a)** `cgm_connect.py` takes `user_id` as a **query parameter** rather than
> from the token (`:72`, `:127`, `:141`, `:157`, `:180`) — any authenticated
> caller can connect, list, or delete another user's CGM. Every one of these
> must move to `Depends(get_current_user)`.
> **(b)** `/ws/glucose/{user_id}` (`glucose_stream.py:132`) performs **no auth at
> all** — the user id comes from the path. Anyone who knows a UUID streams that
> user's glucose. The new `/ws/app/stream` must take the user from the token,
> and the old route must be removed, not merely deprecated.

### 5.2 Libre / CGM connection

| Item | Status | Where |
|---|---|---|
| Libre credential validation + connect | **exists** | `backend/app/api/cgm_connect.py:70`, `services/cgm/libre_service.py:92` |
| Encrypted credential storage | **partial** | `core/secrets_manager.py` is `MockSecretsManager` — in-process dict, non-durable; `core/encryption.py` is real |
| LibreLinkUp client (login/connections/graph) | **exists** | `services/cgm/libre_service.py` |
| Session + region cache | **partial** | `libre_service.py:59` `_sessions` — in-memory per process, no durable region persistence |
| Correct LLU headers | **partial** | `libre_service.py` `_LLU_HEADERS` still `version 4.7.0`, missing `accept-encoding`/`cache-control`/`connection`; correct set is in `device-repo-export/app/services/libre_poller.py` |
| Timestamp → UTC with tz | **exists** | `services/libre_timestamp.py` (`parse_libre_timestamp`, `_resolve_zone`, `libre_timestamp_to_epoch`) |
| No-fake-readings guarantee | **exists** | `_FALLBACK_READING` removed, commit f6883d8 |
| Glucose storage (Timescale hypertable) | **exists** | `migrations/004_glucose_streaming.sql`, `models/glucose_reading.py` |
| Manual glucose entry | **exists** | `backend/app/api/glucose.py:22`, `frontend/lib/features/glucose/providers/manual_glucose_provider.dart` |
| Accu-Chek / manual CGM services | **exists** | `services/cgm/accuchek_service.py`, `manual_service.py`, `factory.py` |
| App connect UI | **exists** | `frontend/lib/features/cgm/**` (`libre_connect_screen.dart`, `cgm_connection_provider.dart`) |
| Live glucose stream to app | **partial** | `/ws/glucose/{user_id}` works but **polls inside the socket handler** (`glucose_stream.py:177`) — no socket, no data; plus the auth hole above |
| **Shared 24/7 poller** | **missing** | the core of §4.3 |
| **Reading dedup / `sensor_id` column** | **missing** | §1.3 |
| **Account registry** | **missing** | §3.2 |
| Device-side poller (to be deleted) | exists, **to remove** | `mytr-desk/device/libred/**`, `device-repo-export/**` |

### 5.3 Apple Health / Google Health Connect

| Item | Status | Where |
|---|---|---|
| iOS/Android health read (steps, active energy, HR) | **exists** | `frontend/lib/core/services/health_service.dart` (`health: ^13.3.1`) |
| Permission request / authorization check | **exists** | `health_service.dart:44`, `:53` |
| Google Health OAuth (PKCE, token storage) | **exists** | `frontend/lib/features/wearables/services/google_health_service.dart` |
| Wearable connection UI | **exists** | `frontend/lib/features/wearables/**` |
| Fitbit client | **exists** | `frontend/lib/features/wearables/services/fitbit_service.dart` |
| Garmin service | **partial** | `backend/app/services/wearables/garmin_service.py` (103 lines, no route wired in `main.py`) |
| App→backend sync call | **partial** | `activity_provider.dart:50` posts `/activity/sync` — **today's aggregate only**, 3 scalars |
| Backend ingest | **partial** | `backend/app/api/activity.py:21` — daily upsert, last-write-wins, no history, no source, no dedup |
| Storage | **partial** | `migrations/009_activity_sync.sql` `activity_logs` — one row/user/day |
| `wearable_devices` table | **exists** | `models/user.py:87` |
| **Time-series health storage** | **missing** | §1.4 |
| **Batch sample ingest endpoint** | **missing** | `POST /api/v1/health/samples` |
| **Health read endpoint** | **missing** | only surfaced inside `/dashboard` |
| **Background sync (iOS observer / Android WorkManager)** | **missing** | sync is foreground-only, on provider build |
| **Sleep, resting HR, weight** | **missing** | `_types` in `health_service.dart:26` covers 3 metrics |

### 5.4 Calorie tracking

| Item | Status | Where |
|---|---|---|
| Meal photo recognition | **exists** | `backend/app/api/nutrition.py:71`, `services/gemini_service.py` |
| Food search (USDA) | **exists** | `nutrition.py:129`, `services/usda_service.py` |
| Log meal (calc macros, persist) | **exists** | `nutrition.py:166`, `:240` |
| Macro/GL enrichment | **exists** | `services/meal_enrichment_service.py` |
| Storage | **exists** | `migrations/002_meal_logs.sql`, `005_add_fiber_to_meal_logs.sql`, `models/meal_log.py` |
| Post-meal glucose outcome job | **exists** | `backend/app/tasks/post_meal.py` |
| App capture/search/correction UI | **exists** | `frontend/lib/features/nutrition/**` |
| Daily totals (in dashboard) | **partial** | computed inside `backend/app/api/dashboard.py:32`, not separately addressable |
| **List meals endpoint** | **missing** | `meal_logs` is write-only over the API |
| **Delete / edit meal** | **missing** | no correction path after save |
| **Daily calorie endpoint** | **missing** | `GET /api/v1/nutrition/daily` |

### 5.5 Device-facing surface

Every row is **missing** — this is the genuinely new build: `devices` +
`device_pairing_codes` tables, device JWT types, `get_current_device`, the four
pairing endpoints, `/device/snapshot`, the four device GETs,
`/device/heartbeat`, `/ws/device/stream`, the fanout hub with `seq`/replay, and
the relocated voice proxy.

### 5.6 Net: build only these

1. **Backend, auth:** device token types, `devices`/`device_pairing_codes`,
   `get_current_device`, pairing endpoints; fix the `cgm_connect.py` `user_id`
   query-param hole and the unauthenticated glucose websocket.
2. **Backend, ingestion:** `LibreIngestionService` + account registry +
   per-user timezone + reading dedup + durable secrets store; delete the
   in-socket polling loop.
3. **Backend, fanout:** hub with `seq`/replay; `/ws/app/stream` and
   `/ws/device/stream` on top of it.
4. **Backend, health:** `health_metrics`, `POST /health/samples`,
   `GET /health/daily`, `activity_logs` as projection.
5. **Backend, nutrition:** meals list/delete + `GET /nutrition/daily`.
6. **Backend, device reads:** `/device/snapshot` + four GETs + heartbeat.
7. **Backend, voice:** relocate the proxy, re-auth it, inject glucose context
   server-side.
8. **App:** pairing UI + device management; switch health sync to
   `/health/samples`; add background sync; broaden metrics; move `/ws/glucose`
   to `/ws/app/stream`.
9. **Device:** `syncd` replacing `libred`; pairing screen replacing the
   credentials screen; health + calorie panels; retarget `mockserver`.
   `alarmd` untouched.
