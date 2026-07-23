# LibreLinkUp poller consolidation — one poller, two sinks (Phase 5.5)

## Why

Right now two independent code paths poll LibreLinkUp:

1. **Mobile path** — `app/services/cgm/libre_service.py`, driven by the
   `/ws/glucose/{user_id}` websocket (`app/api/websockets/glucose_stream.py`).
   Polls **per-user** credentials (`libre:{user_id}` in the secrets manager),
   only while a mobile socket is open, and writes to TimescaleDB
   `glucose_readings`.
2. **Device path** — `app/services/libre_poller.py`, started in-process by
   `app/device_runtime.py`. Polls **one** backend `.env` account 24/7 and writes
   to `device_readings` + publishes to the stream hub.

When the `.env` account is also a user's connected account (certain in
dev/test, possible in prod), both loops hit the **same Abbott account**, which
risks rate-limiting/temporary blocks and produces divergent data between the two
stores. And it can't stay this way: a desk device paired to user X must stream
**X's** glucose, i.e. X's LibreLinkUp account — not a shared `.env` account. So
the device poller has to become per-paired-user, at which point it is polling
the exact same account the mobile path already polls. Consolidation is therefore
a correctness requirement, not just an optimization.

### Already done (interim guardrail, this branch)

On `phase-5-device-pipeline`, in `libre_service.py`:

- **No synthesized readings.** `_FALLBACK_READING` removed. Any fetch failure
  raises `LibreServiceError`; the websocket consumer already surfaces a
  no-data/stale `CGM_ERROR` state. A fabricated glucose value is a safety
  hazard and is gone.
- **Login-storm fixed.** Token + working region are cached per user
  (`_sessions`); each poll is now one logged-in request instead of re-scanning
  all six regional hosts and re-logging-in every 60 s. A 401 drops the cached
  session and forces exactly one re-login.
- **Timestamp parse fixed.** The naive-as-UTC `strptime` is replaced with the
  poller's tz-resolving `libre_timestamp_to_epoch`, so readings are stamped in
  correct UTC (previously off by the account's UTC offset).

Interim limitations that consolidation must resolve:

- The mobile path resolves timestamps against the single
  `LIBRE_ACCOUNT_TIMEZONE` setting, not a **per-user** timezone.
- The region cache is in-memory (per websocket session); the first poll still
  scans regions once.
- `_LLU_HEADERS` is still `version 4.7.0` and lacks the
  `accept-encoding`/`cache-control`/`connection` headers the real client sends
  (`docs/data-format.md`); the device poller already has these correct.
- The device poller still runs on the shared `.env` account.

## Target design: one ingestion, two sinks

```
                       ┌─────────────────────────────────────────┐
   per-user Libre creds │           LibreIngestionService          │
   (secrets manager) ──▶│  one poll loop per distinct account:     │
                        │  login (cached token+region) → connections│
                        │  → graph → normalize (tz→UTC, trend label)│
                        └───────────────┬─────────────┬────────────┘
                                        │             │
                         Sink A (mobile)│             │Sink B (device)
                                        ▼             ▼
                          TimescaleDB glucose_readings   device_readings
                          (per user_id)                  + hub.publish(...)
```

### Components

1. **`LibreIngestionService`** — the single LibreLinkUp client + poll loop.
   - Fold `libre_poller.LibreLinkUpClient` and `libre_service`'s HTTP logic into
     one client with the correct headers (`version 4.16.0` + `accept-encoding`/
     `cache-control`/`connection`), token caching, and durable
     per-account region persistence.
   - Normalize once via the shared `libre_timestamp_to_epoch` + `map_trend_arrow`
     (extract these pure helpers into `app/services/libre_timestamp.py` so there
     is a single source of truth; `libre_poller` re-exports them for its tests).
   - One loop **per distinct account**, deduped by credentials, so an account is
     polled exactly once regardless of how many devices/sessions reference it.

2. **Account registry** — what to poll.
   - Source per-user credentials from the secrets manager (the mobile app already
     stores them at connect time, `cgm_connect.py`).
   - A paired desk device contributes its **paired user's** account (join
     `devices.user_id` → that user's `libre:{user_id}` creds). The `.env` account
     becomes a dev/standalone default only.
   - Track, per account, the target `sensor_id`(s) and `user_id`(s) so fan-out
     knows where each reading goes.

3. **Per-user timezone** — resolve each account's timezone rather than one global
   setting. Prefer LibreLinkUp's own account/profile timezone if exposed;
   otherwise store it per user at connect time (a column on the CGM device / the
   secrets record). This removes the interim `LIBRE_ACCOUNT_TIMEZONE` assumption.

4. **Sink A — mobile / TimescaleDB.** Upsert normalized readings into
   `glucose_readings` keyed by `(user_id, sensor_id, recorded_at)`. The
   `/ws/glucose/{user_id}` websocket **stops polling**: it subscribes to the
   ingestion output (or reads latest-from-store), so the live card no longer
   depends on the poll cadence being tied to a foregrounded app, and the
   fresh-login-per-poll behavior is gone entirely.

5. **Sink B — device.** Upsert into `device_readings` (existing dedup on
   `(sensor_id, ts)`) and `hub.publish(...)` — unchanged from Phase 5, now fed by
   the shared ingestion instead of a separate loop.

### Cross-cutting

- **Rate-limit hygiene:** single-flight per account, backoff with jitter on 429,
  and a circuit breaker that surfaces a stale state (never a fake reading) when
  an account is temporarily blocked.
- **Observability:** per-account last-success timestamp + failure reason, so a
  rate-limit block is visible rather than silent.

## Migration steps (as its own scoped phase)

1. Extract `app/services/libre_timestamp.py` (pure parse + trend helpers);
   point `libre_poller` and `libre_service` at it.
2. Build `LibreIngestionService` (client + per-account loop + fan-out), reusing
   the Phase 5 poller mechanics.
3. Add the account registry (per-user creds + paired-device join) and per-user
   timezone resolution.
4. Switch Sink A on: ingestion writes `glucose_readings`; convert
   `/ws/glucose/{user_id}` from poller to subscriber/reader.
5. Switch Sink B on: point device stream/backfill at the shared ingestion;
   retire the standalone `.env`-only device poller loop (keep `.env` as dev
   default).
6. Delete the now-dead polling code in `libre_service`/`glucose_stream`.
7. Load-test against a single real account to confirm one login+query stream and
   no rate-limit trips.

## Sequencing

Insert as **Phase 5.5 — after voice (Phase 4), before the Pi burn-in.** It must
land **before any desk device reaches a real user**: a paired device has to
stream its own user's glucose, which the current shared-`.env` device poller
cannot do. The interim guardrail on this branch makes the mobile path safe and
quiet in the meantime, but it does not remove the two-poller topology.

> Note for the real-credentials run: because both pollers currently hit Abbott
> on the same account, you may see rate-limiting (flaky/absent readings). That's
> the two-poller topology described here, not a bug in the pipeline code —
> consolidation is what removes it.
