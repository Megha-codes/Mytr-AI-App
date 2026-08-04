"""Phase A capstone: the four things architecture-v3.md §2.6 asks this pass
to prove, end to end, through the *real* wired production paths
(LibreIngestionService.poll_account_once and POST /glucose/manual's
log_manual_glucose) sharing one FanoutHub instance — not the hub tested in
isolation.

1. Two subscribers on the same user_id both receive a published reading, in
   order.
2. A subscriber on a different user_id receives nothing (isolation).
3. Resume replays missed readings correctly.
4. Manual and Libre readings both flow through identically.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import app.api.glucose as glucose_module
import httpx
from app.api.glucose import ManualGlucoseRequest, log_manual_glucose
from app.core.encryption import encrypt
from app.core.secrets_manager import secrets_manager
from app.models.user import CGMDevice, LoginAttempt
from app.services.cgm.libre_account_registry import get_eligible_accounts, group_by_credential
from app.services.cgm.libre_ingestion_service import LibreIngestionService
from app.services.realtime.fanout_hub import FanoutHub

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user

LIBRE_EMAIL = "proof-account@example.com"


def _libre_ts(dt: datetime) -> str:
    """Formats a datetime as LibreLinkUp's raw `M/D/YYYY H:MM:SS AM/PM`
    string — resume()'s 24h window is relative to the real clock, so tests
    must use timestamps near "now", not an arbitrary fixed calendar date."""
    hour12 = dt.hour % 12 or 12
    period = "AM" if dt.hour < 12 else "PM"
    return f"{dt.month}/{dt.day}/{dt.year} {hour12}:{dt.minute:02d}:{dt.second:02d} {period}"


def _libre_transport(readings: list):
    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.endswith("/auth/login"):
            return httpx.Response(200, json={"data": {"authTicket": {"token": "tok"}, "user": {"id": "uid"}}})
        if path.endswith("/connections"):
            return httpx.Response(
                200, json={"data": [{"patientId": "patient-1", "sensor": {"sn": "sensor-1"}}]}
            )
        if path.endswith("/graph"):
            return httpx.Response(200, json={"data": {"graphData": readings}})
        return httpx.Response(404)
    return handler


async def test_fanout_hub_proof(monkeypatch):
    db_engine, db_session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()

    watched_user = await make_user(db_session_factory, "watched-user@example.com")
    other_user = await make_user(db_session_factory, "other-user@example.com")

    async with db_session_factory() as db:
        db.add(CGMDevice(user_id=watched_user.id, device_type="LIBRE_3", is_active=True))
        db.add(LoginAttempt(
            email=watched_user.email, ip="1.2.3.4", successful=True, created_at=datetime.utcnow(),
        ))
        await db.commit()
    await secrets_manager.store_libre_credentials(str(watched_user.id), LIBRE_EMAIL, encrypt("pw"))

    async with db_session_factory() as db:
        accounts = await get_eligible_accounts(db)
    group_accounts = group_by_credential(accounts)[LIBRE_EMAIL]

    hub = FanoutHub()
    monkeypatch.setattr(glucose_module, "fanout_hub", hub)
    monkeypatch.setattr(glucose_module, "TimescaleSessionLocal", ts_session_factory)

    ingestion_service = LibreIngestionService(
        db_session_factory=db_session_factory,
        timescale_session_factory=ts_session_factory,
        fanout_hub=hub,
    )

    # ── Two subscribers on the same user, one on a different user ──────────
    queue_a = hub.subscribe(watched_user.id)
    queue_b = hub.subscribe(watched_user.id)
    other_queue = hub.subscribe(other_user.id)

    now = datetime.now(timezone.utc)

    # ── A Libre reading ingests and flows to both watched-user subscribers ─
    first_reading = [{"Timestamp": _libre_ts(now - timedelta(minutes=20)), "Value": 118, "TrendArrow": 3}]
    ingestion_service._client = lambda: httpx.AsyncClient(
        transport=httpx.MockTransport(_libre_transport(first_reading)), timeout=15.0
    )
    written = await ingestion_service.poll_account_once(LIBRE_EMAIL, group_accounts)
    assert written == 1

    frames_a = [queue_a.get_nowait(), queue_a.get_nowait()]  # glucose.reading, glucose.state
    frames_b = [queue_b.get_nowait(), queue_b.get_nowait()]
    assert frames_a == frames_b  # (1) same user, same events, same order
    assert frames_a[0]["type"] == "glucose.reading"
    assert frames_a[0]["data"]["mgdl"] == 118
    assert frames_a[0]["data"]["source"] == "LIBRE"
    assert frames_a[1]["type"] == "glucose.state"

    # (2) isolation — the other user's subscriber saw none of that.
    assert other_queue.empty()

    libre_checkpoint_seq = frames_a[0]["seq"]

    # ── queue_b "disconnects" (unsubscribes) before the next readings ──────
    hub.unsubscribe(watched_user.id, queue_b)

    second_reading_time = now - timedelta(minutes=10)
    async with db_session_factory() as db:
        await log_manual_glucose(
            ManualGlucoseRequest(value_mgdl=140, timestamp=second_reading_time),
            current_user=watched_user,
            db=db,
        )
    manual_frame = queue_a.get_nowait()  # queue_b missed this — it's gone

    # (4) manual and Libre flow through identically: same shape, only
    # source/sensor_id differ, and manual entries participate in the same
    # ordered glucose.reading stream (checked again below via resume).
    assert manual_frame["type"] == "glucose.reading"
    assert set(manual_frame["data"].keys()) == set(frames_a[0]["data"].keys())
    assert manual_frame["data"]["source"] == "MANUAL"
    assert manual_frame["data"]["sensor_id"] is None
    assert manual_frame["data"]["mgdl"] == 140

    # A second Libre reading, also missed by the disconnected queue_b.
    third_reading = [
        {"Timestamp": _libre_ts(now - timedelta(minutes=20)), "Value": 118, "TrendArrow": 3},  # already seen — no-op
        {"Timestamp": _libre_ts(now - timedelta(minutes=1)), "Value": 122, "TrendArrow": 4},  # new
    ]
    ingestion_service._client = lambda: httpx.AsyncClient(
        transport=httpx.MockTransport(_libre_transport(third_reading)), timeout=15.0
    )
    await ingestion_service.poll_account_once(LIBRE_EMAIL, group_accounts)
    third_reading_frame = queue_a.get_nowait()
    queue_a.get_nowait()  # its glucose.state
    assert third_reading_frame["data"]["mgdl"] == 122
    assert queue_a.empty()

    # ── (3) resume: queue_b reconnects and must get exactly what it missed —
    # the manual 140 reading and the Libre 122 reading, in order, not the
    # first Libre 118 reading again.
    result = await hub.resume(watched_user.id, since_seq=libre_checkpoint_seq, session_factory=ts_session_factory)
    assert result.resync is False
    replayed_values = [f["data"]["mgdl"] for f in result.envelopes]
    assert replayed_values == [140, 122]
    assert all(f["type"] == "glucose.reading" for f in result.envelopes)

    await db_engine.dispose()
    await ts_engine.dispose()
