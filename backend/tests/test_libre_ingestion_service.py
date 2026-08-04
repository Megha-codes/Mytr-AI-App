"""Proof tests for LibreIngestionService against a mock LibreLinkUp backend
with two distinct accounts (architecture-v3.md §4.3):

- exactly one login per account per service lifetime, even across many
  poll cycles (session/region caching)
- no duplicate rows even when the same overlapping graph window is
  re-fetched every cycle (the dedup index doing its job)
- correct, independently-resolved per-user timestamps (not a single
  global timezone)
- a restarted service (fresh in-process cache) reuses the durably
  persisted region instead of re-scanning all six regional hosts
"""

from __future__ import annotations

import json
import uuid
from collections import defaultdict
from datetime import datetime, timezone

import httpx
import pytest
from sqlalchemy import select

from app.core.encryption import encrypt
from app.core.secrets_manager import secrets_manager
from app.models.user import CGMDevice, LoginAttempt
from app.models.glucose_reading import GlucoseReadingModel
from app.services.cgm.libre_account_registry import get_eligible_accounts, group_by_credential
from app.services.cgm.libre_ingestion_service import LibreIngestionService
from app.services.libre_timestamp import libre_timestamp_to_epoch

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user

ACCOUNT_A_EMAIL = "kolkata-user@example.com"
ACCOUNT_B_EMAIL = "newyork-user@example.com"
ACCOUNT_A_REGION = "https://api-eu.libreview.io"
ACCOUNT_B_REGION = "https://api-au.libreview.io"
RAW_TIMESTAMP = "6/9/2024 3:45:12 PM"  # same raw string, different accounts


def _build_mock_transport(call_counts, region_attempts, readings_by_email):
    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        base = f"{request.url.scheme}://{request.url.host}"

        if path.endswith("/auth/login"):
            body = json.loads(request.content)
            email = body["email"]
            region_attempts[email].append(base)
            correct_region = {
                ACCOUNT_A_EMAIL: ACCOUNT_A_REGION,
                ACCOUNT_B_EMAIL: ACCOUNT_B_REGION,
            }.get(email)
            if base != correct_region:
                return httpx.Response(401, json={"error": "wrong region for this account"})
            call_counts[email]["login"] += 1
            return httpx.Response(
                200,
                json={"data": {"authTicket": {"token": f"tok::{email}"}, "user": {"id": "uid"}}},
            )

        if path.endswith("/connections"):
            token = request.headers.get("authorization", "").replace("Bearer ", "")
            email = token.split("::", 1)[1]
            call_counts[email]["connections"] += 1
            return httpx.Response(
                200,
                json={
                    "data": [
                        {
                            "patientId": f"patient::{email}",
                            "sensor": {"sn": f"sensor::{email}"},
                        }
                    ]
                },
            )

        if path.endswith("/graph"):
            patient_id = path.split("/")[3]
            email = patient_id.split("::", 1)[1]
            call_counts[email]["graph"] += 1
            return httpx.Response(200, json={"data": {"graphData": readings_by_email[email]}})

        return httpx.Response(404)

    return handler


def _mock_client_factory(handler):
    def _factory():
        return httpx.AsyncClient(transport=httpx.MockTransport(handler), timeout=15.0)
    return _factory


@pytest.fixture
async def two_account_setup():
    engine, session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()

    user_a = await make_user(session_factory, "app-user-a@example.com")
    user_b = await make_user(session_factory, "app-user-b@example.com")

    async with session_factory() as session:
        # user_a: America/New_York (per-user timezone, distinct from user_b)
        result = await session.execute(select(type(user_a)).where(type(user_a).id == user_a.id))
        ua = result.scalar_one()
        ua.timezone = "Asia/Kolkata"
        result = await session.execute(select(type(user_b)).where(type(user_b).id == user_b.id))
        ub = result.scalar_one()
        ub.timezone = "America/New_York"

        cgm_a = CGMDevice(user_id=user_a.id, device_type="LIBRE_3", is_active=True)
        cgm_b = CGMDevice(user_id=user_b.id, device_type="LIBRE_3", is_active=True)
        session.add_all([cgm_a, cgm_b])

        # Recent successful login — the account-registry bound (§3.2) that
        # excludes accounts with neither an active desk device nor recent
        # app activity from unbounded Abbott polling.
        now = datetime.utcnow()
        session.add_all([
            LoginAttempt(email=ua.email, ip="1.2.3.4", successful=True, created_at=now),
            LoginAttempt(email=ub.email, ip="1.2.3.4", successful=True, created_at=now),
        ])

        await session.commit()
        await session.refresh(cgm_a)
        await session.refresh(cgm_b)

    await secrets_manager.store_libre_credentials(str(user_a.id), ACCOUNT_A_EMAIL, encrypt("pw-a"))
    await secrets_manager.store_libre_credentials(str(user_b.id), ACCOUNT_B_EMAIL, encrypt("pw-b"))

    readings_by_email = {
        ACCOUNT_A_EMAIL: [{"Timestamp": RAW_TIMESTAMP, "Value": 110, "TrendArrow": 3}],
        ACCOUNT_B_EMAIL: [{"Timestamp": RAW_TIMESTAMP, "Value": 145, "TrendArrow": 4}],
    }
    call_counts = defaultdict(lambda: {"login": 0, "connections": 0, "graph": 0})
    region_attempts = defaultdict(list)

    yield {
        "session_factory": session_factory,
        "ts_session_factory": ts_session_factory,
        "user_a": user_a,
        "user_b": user_b,
        "cgm_a_id": cgm_a.id,
        "cgm_b_id": cgm_b.id,
        "call_counts": call_counts,
        "region_attempts": region_attempts,
        "readings_by_email": readings_by_email,
    }

    await engine.dispose()
    await ts_engine.dispose()


async def _get_groups(session_factory):
    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    return group_by_credential(accounts)


async def test_one_login_per_account_across_multiple_poll_cycles(two_account_setup):
    ctx = two_account_setup
    handler = _build_mock_transport(ctx["call_counts"], ctx["region_attempts"], ctx["readings_by_email"])
    service = LibreIngestionService(
        db_session_factory=ctx["session_factory"],
        timescale_session_factory=ctx["ts_session_factory"],
    )
    service._client = _mock_client_factory(handler)

    groups = await _get_groups(ctx["session_factory"])
    assert set(groups.keys()) == {ACCOUNT_A_EMAIL, ACCOUNT_B_EMAIL}

    # Three poll cycles per account, same service instance (session cached).
    for _ in range(3):
        for email, accounts in groups.items():
            await service.poll_account_once(email, accounts)

    assert ctx["call_counts"][ACCOUNT_A_EMAIL]["login"] == 1
    assert ctx["call_counts"][ACCOUNT_B_EMAIL]["login"] == 1
    assert ctx["call_counts"][ACCOUNT_A_EMAIL]["connections"] == 3
    assert ctx["call_counts"][ACCOUNT_B_EMAIL]["connections"] == 3
    assert ctx["call_counts"][ACCOUNT_A_EMAIL]["graph"] == 3
    assert ctx["call_counts"][ACCOUNT_B_EMAIL]["graph"] == 3


async def test_no_duplicate_rows_across_overlapping_poll_cycles(two_account_setup):
    ctx = two_account_setup
    handler = _build_mock_transport(ctx["call_counts"], ctx["region_attempts"], ctx["readings_by_email"])
    service = LibreIngestionService(
        db_session_factory=ctx["session_factory"],
        timescale_session_factory=ctx["ts_session_factory"],
    )
    service._client = _mock_client_factory(handler)

    groups = await _get_groups(ctx["session_factory"])

    # Five cycles, identical graph data every time (a real overlapping window).
    for _ in range(5):
        for email, accounts in groups.items():
            await service.poll_account_once(email, accounts)

    async with ctx["ts_session_factory"]() as ts_db:
        result_a = await ts_db.execute(
            select(GlucoseReadingModel).where(GlucoseReadingModel.user_id == ctx["user_a"].id)
        )
        result_b = await ts_db.execute(
            select(GlucoseReadingModel).where(GlucoseReadingModel.user_id == ctx["user_b"].id)
        )
        assert len(result_a.scalars().all()) == 1
        assert len(result_b.scalars().all()) == 1


async def test_per_user_timestamps_resolved_independently(two_account_setup):
    ctx = two_account_setup
    handler = _build_mock_transport(ctx["call_counts"], ctx["region_attempts"], ctx["readings_by_email"])
    service = LibreIngestionService(
        db_session_factory=ctx["session_factory"],
        timescale_session_factory=ctx["ts_session_factory"],
    )
    service._client = _mock_client_factory(handler)

    groups = await _get_groups(ctx["session_factory"])
    for email, accounts in groups.items():
        await service.poll_account_once(email, accounts)

    expected_a = datetime.fromtimestamp(
        libre_timestamp_to_epoch(RAW_TIMESTAMP, "Asia/Kolkata"), tz=timezone.utc
    )
    expected_b = datetime.fromtimestamp(
        libre_timestamp_to_epoch(RAW_TIMESTAMP, "America/New_York"), tz=timezone.utc
    )
    assert expected_a != expected_b  # sanity: the two timezones actually differ here

    async with ctx["ts_session_factory"]() as ts_db:
        row_a = (
            await ts_db.execute(
                select(GlucoseReadingModel).where(GlucoseReadingModel.user_id == ctx["user_a"].id)
            )
        ).scalar_one()
        row_b = (
            await ts_db.execute(
                select(GlucoseReadingModel).where(GlucoseReadingModel.user_id == ctx["user_b"].id)
            )
        ).scalar_one()

    assert row_a.recorded_at == expected_a
    assert row_b.recorded_at == expected_b
    assert row_a.value_mgdl == 110
    assert row_b.value_mgdl == 145


async def test_restart_reuses_persisted_region_without_rescanning(two_account_setup):
    """A fresh service instance (simulating a process restart, so its
    in-memory session cache is empty) must go straight to the durably
    cached region_base instead of scanning all six hosts again."""
    ctx = two_account_setup
    handler = _build_mock_transport(ctx["call_counts"], ctx["region_attempts"], ctx["readings_by_email"])

    service = LibreIngestionService(
        db_session_factory=ctx["session_factory"],
        timescale_session_factory=ctx["ts_session_factory"],
    )
    service._client = _mock_client_factory(handler)
    groups = await _get_groups(ctx["session_factory"])
    for email, accounts in groups.items():
        await service.poll_account_once(email, accounts)

    # Region must now be persisted on cgm_devices.
    async with ctx["session_factory"]() as db:
        cgm_a = (await db.execute(select(CGMDevice).where(CGMDevice.id == ctx["cgm_a_id"]))).scalar_one()
        cgm_b = (await db.execute(select(CGMDevice).where(CGMDevice.id == ctx["cgm_b_id"]))).scalar_one()
    assert cgm_a.region_base == ACCOUNT_A_REGION
    assert cgm_b.region_base == ACCOUNT_B_REGION

    # Simulate a restart: brand-new service, empty in-process cache.
    ctx["region_attempts"].clear()
    restarted_service = LibreIngestionService(
        db_session_factory=ctx["session_factory"],
        timescale_session_factory=ctx["ts_session_factory"],
    )
    restarted_service._client = _mock_client_factory(handler)
    for email, accounts in groups.items():
        await restarted_service.poll_account_once(email, accounts)

    # Exactly one region attempt per account this round — the correct one,
    # on the first try, not a scan through the other five.
    assert ctx["region_attempts"][ACCOUNT_A_EMAIL] == [ACCOUNT_A_REGION]
    assert ctx["region_attempts"][ACCOUNT_B_EMAIL] == [ACCOUNT_B_REGION]


async def test_dead_credentials_do_not_crash_the_poll_loop(two_account_setup):
    """A login that fails for every region (revoked Abbott password, etc.)
    must be handled gracefully — no exception, no readings written."""
    ctx = two_account_setup

    def all_fail_handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": "invalid credentials"})

    service = LibreIngestionService(
        db_session_factory=ctx["session_factory"],
        timescale_session_factory=ctx["ts_session_factory"],
    )
    service._client = _mock_client_factory(all_fail_handler)

    groups = await _get_groups(ctx["session_factory"])
    for email, accounts in groups.items():
        written = await service.poll_account_once(email, accounts)
        assert written == 0

    async with ctx["ts_session_factory"]() as ts_db:
        result = await ts_db.execute(select(GlucoseReadingModel))
        assert result.scalars().all() == []
