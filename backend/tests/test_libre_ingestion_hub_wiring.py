"""Proves LibreIngestionService publishes through FanoutHub on ingest
(architecture-v3.md §2.6): glucose.reading + glucose.state for every newly
written reading, and — critically — nothing at all for readings the poller
has already seen (duplicate re-fetches of an overlapping graph window).
"""

from __future__ import annotations

from datetime import datetime

import httpx
import pytest

from app.core.encryption import encrypt
from app.core.secrets_manager import secrets_manager
from app.models.user import CGMDevice, LoginAttempt
from app.services.cgm.libre_account_registry import get_eligible_accounts, group_by_credential
from app.services.cgm.libre_ingestion_service import LibreIngestionService
from app.services.realtime.fanout_hub import FanoutHub

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user

ACCOUNT_EMAIL = "hub-wiring@example.com"
ACCOUNT_REGION = "https://api.libreview.io"


def _build_transport(readings: list, call_counts: dict):
    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.endswith("/auth/login"):
            call_counts["login"] += 1
            return httpx.Response(
                200, json={"data": {"authTicket": {"token": "tok"}, "user": {"id": "uid"}}}
            )
        if path.endswith("/connections"):
            call_counts["connections"] += 1
            return httpx.Response(
                200,
                json={"data": [{"patientId": "patient-1", "sensor": {"sn": "sensor-1"}}]},
            )
        if path.endswith("/graph"):
            call_counts["graph"] += 1
            return httpx.Response(200, json={"data": {"graphData": readings}})
        return httpx.Response(404)

    return handler


def _mock_client_factory(handler):
    def _factory():
        return httpx.AsyncClient(transport=httpx.MockTransport(handler), timeout=15.0)
    return _factory


@pytest.fixture
async def wiring_setup():
    engine, session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()

    user = await make_user(session_factory, "hub-wiring-user@example.com")
    async with session_factory() as session:
        session.add(CGMDevice(user_id=user.id, device_type="LIBRE_3", is_active=True))
        session.add(LoginAttempt(
            email=user.email, ip="1.2.3.4", successful=True, created_at=datetime.utcnow(),
        ))
        await session.commit()
    await secrets_manager.store_libre_credentials(str(user.id), ACCOUNT_EMAIL, encrypt("pw"))

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    groups = group_by_credential(accounts)
    group_accounts = groups[ACCOUNT_EMAIL]

    yield {
        "session_factory": session_factory,
        "ts_session_factory": ts_session_factory,
        "user": user,
        "group_accounts": group_accounts,
    }

    await engine.dispose()
    await ts_engine.dispose()


async def test_new_reading_publishes_glucose_reading_and_glucose_state(wiring_setup):
    ctx = wiring_setup
    hub = FanoutHub()
    queue = hub.subscribe(ctx["user"].id)

    call_counts = {"login": 0, "connections": 0, "graph": 0}
    readings = [{"Timestamp": "6/9/2024 3:45:12 PM", "Value": 118, "TrendArrow": 3}]
    service = LibreIngestionService(
        db_session_factory=ctx["session_factory"],
        timescale_session_factory=ctx["ts_session_factory"],
        fanout_hub=hub,
    )
    service._client = _mock_client_factory(_build_transport(readings, call_counts))

    written = await service.poll_account_once(ACCOUNT_EMAIL, ctx["group_accounts"])
    assert written == 1

    reading_frame = queue.get_nowait()
    state_frame = queue.get_nowait()
    assert queue.empty()

    assert reading_frame["type"] == "glucose.reading"
    assert reading_frame["data"]["mgdl"] == 118
    assert reading_frame["data"]["sensor_id"] == "sensor-1"
    assert reading_frame["data"]["source"] == "LIBRE"

    assert state_frame["type"] == "glucose.state"
    assert state_frame["data"]["state"] == "LIVE"

    # glucose.reading is published before glucose.state, and seq is
    # monotonic across both.
    assert reading_frame["seq"] < state_frame["seq"]


async def test_duplicate_reading_on_a_later_poll_is_not_republished(wiring_setup):
    ctx = wiring_setup
    hub = FanoutHub()
    queue = hub.subscribe(ctx["user"].id)

    call_counts = {"login": 0, "connections": 0, "graph": 0}
    readings = [{"Timestamp": "6/9/2024 3:45:12 PM", "Value": 118, "TrendArrow": 3}]
    service = LibreIngestionService(
        db_session_factory=ctx["session_factory"],
        timescale_session_factory=ctx["ts_session_factory"],
        fanout_hub=hub,
    )
    service._client = _mock_client_factory(_build_transport(readings, call_counts))

    await service.poll_account_once(ACCOUNT_EMAIL, ctx["group_accounts"])
    assert queue.qsize() == 2  # reading + state from the first (new) poll

    # Drain, then poll again with the *same* overlapping graph window.
    queue.get_nowait()
    queue.get_nowait()

    second_written = await service.poll_account_once(ACCOUNT_EMAIL, ctx["group_accounts"])
    assert second_written == 0
    assert queue.empty()  # nothing published for an already-seen reading


async def test_two_new_readings_in_one_poll_publish_two_reading_frames(wiring_setup):
    ctx = wiring_setup
    hub = FanoutHub()
    queue = hub.subscribe(ctx["user"].id)

    call_counts = {"login": 0, "connections": 0, "graph": 0}
    readings = [
        {"Timestamp": "6/9/2024 3:40:00 PM", "Value": 100, "TrendArrow": 3},
        {"Timestamp": "6/9/2024 3:45:00 PM", "Value": 105, "TrendArrow": 4},
    ]
    service = LibreIngestionService(
        db_session_factory=ctx["session_factory"],
        timescale_session_factory=ctx["ts_session_factory"],
        fanout_hub=hub,
    )
    service._client = _mock_client_factory(_build_transport(readings, call_counts))

    written = await service.poll_account_once(ACCOUNT_EMAIL, ctx["group_accounts"])
    assert written == 2

    frames = []
    while not queue.empty():
        frames.append(queue.get_nowait())

    reading_frames = [f for f in frames if f["type"] == "glucose.reading"]
    assert [f["data"]["mgdl"] for f in reading_frames] == [100, 105]
