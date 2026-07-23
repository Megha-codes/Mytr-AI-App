"""Tests for the mobile LibreLinkUp path (app/services/cgm/libre_service.py)
interim guardrail:

- no synthesized reading on API failure — it raises LibreServiceError instead;
- the US-style timestamp is resolved through the account timezone (same logic
  as the device poller), not the old naive-as-UTC parse;
- token + region are cached, so repeated polls don't re-scan/re-login.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import httpx
import pytest

from app.core.config import settings
from app.core.encryption import encrypt
from app.core.secrets_manager import secrets_manager
# Import factory first so the factory<->libre_service module cycle resolves the
# same way it does in the running app (glucose_stream imports factory at startup).
import app.services.cgm.factory  # noqa: F401
from app.services.cgm.libre_service import LibreCGMService, LibreServiceError


def _install_creds(user_id: str):
    return secrets_manager.store_libre_credentials(user_id, "user@example.com", encrypt("pw"))


def _mock_client_factory(handler):
    def _factory():
        return httpx.AsyncClient(transport=httpx.MockTransport(handler), timeout=15.0)
    return _factory


def test_fallback_reading_constant_is_gone():
    # The synthetic reading must not exist anywhere in the module.
    import app.services.cgm.libre_service as mod
    assert not hasattr(mod, "_FALLBACK_READING")


async def test_no_reading_synthesized_on_api_failure():
    user_id = str(uuid.uuid4())
    await _install_creds(user_id)

    def handler(request: httpx.Request) -> httpx.Response:
        # Every regional login fails -> no session can be established.
        return httpx.Response(500, json={"error": "down"})

    service = LibreCGMService()
    service._client = _mock_client_factory(handler)

    with pytest.raises(LibreServiceError):
        await service.get_latest_reading(user_id)


async def test_timestamp_resolved_through_account_timezone(monkeypatch):
    # 3:45:12 PM in Asia/Kolkata (UTC+5:30) is 10:15:12 UTC. The old naive parse
    # would have read it as 15:45:12 "UTC" — >5h from the target below, so it
    # would fall outside tolerance and return None. Getting the reading back
    # (with an aware UTC timestamp) proves the tz-resolving parse is in effect.
    monkeypatch.setattr(settings, "LIBRE_ACCOUNT_TIMEZONE", "Asia/Kolkata")
    service = LibreCGMService()

    readings = [{"Timestamp": "6/9/2024 3:45:12 PM", "Value": 142, "TrendArrow": 4}]
    target = datetime(2024, 6, 9, 10, 15, 10)  # naive UTC, ~2s from the reading

    reading = service._find_closest_reading(readings, target, tolerance_minutes=6)

    assert reading is not None
    assert reading.value == 142
    assert reading.timestamp.tzinfo is not None
    assert reading.timestamp == datetime(2024, 6, 9, 10, 15, 12, tzinfo=timezone.utc)


async def test_session_cached_across_polls(monkeypatch):
    monkeypatch.setattr(settings, "LIBRE_ACCOUNT_TIMEZONE", "")  # UTC
    user_id = str(uuid.uuid4())
    await _install_creds(user_id)

    counts = {"login": 0, "connections": 0, "graph": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.endswith("/auth/login"):
            counts["login"] += 1
            return httpx.Response(
                200, json={"data": {"authTicket": {"token": "tok"}, "user": {"id": "uid"}}}
            )
        if path.endswith("/connections"):
            counts["connections"] += 1
            return httpx.Response(200, json={"data": [{"patientId": "p1"}]})
        if path.endswith("/graph"):
            counts["graph"] += 1
            # An old reading — outside tolerance, so get_latest_reading returns
            # None (a legitimate no-data result, not an error).
            return httpx.Response(
                200,
                json={"data": {"graphData": [
                    {"Timestamp": "1/1/2020 12:00:00 PM", "Value": 100, "TrendArrow": 3}
                ]}},
            )
        return httpx.Response(404)

    service = LibreCGMService()
    service._client = _mock_client_factory(handler)

    assert await service.get_latest_reading(user_id) is None
    assert await service.get_latest_reading(user_id) is None
    assert await service.get_latest_reading(user_id) is None

    # First regional host answers 200, so exactly one login total; it's cached
    # thereafter, while connections/graph run every poll.
    assert counts["login"] == 1
    assert counts["connections"] == 3
    assert counts["graph"] == 3
