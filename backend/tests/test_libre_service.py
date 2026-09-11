"""Tests for the mobile LibreLinkUp path (app/services/cgm/libre_service.py)
interim guardrail:

- no synthesized reading on API failure — it raises LibreServiceError instead;
- the US-style timestamp is resolved through the account timezone (same logic
  as the device poller), not the old naive-as-UTC parse;
- token + region are cached, so repeated polls don't re-scan/re-login.
"""

from __future__ import annotations

import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import httpx
import pytest

from app.core.config import settings
from app.core.encryption import encrypt
from app.core.secrets_manager import secrets_manager
from app.services.cgm.libre_service import LibreCGMService, LibreServiceError


def _install_creds(user_id: str):
    return secrets_manager.store_libre_credentials(user_id, "user@example.com", encrypt("pw"))


def _mock_client_factory(handler):
    def _factory():
        return httpx.AsyncClient(transport=httpx.MockTransport(handler), timeout=15.0)
    return _factory


def test_libre_service_imports_standalone_without_factory():
    """Regression test for a real circular-import crash: libre_service.py
    used to import BaseCGMService/CGMReading from .factory, while
    factory.py imported LibreCGMService from .libre_service at module
    level — whichever module Python loaded first would fail with
    "ImportError: cannot import name ... from partially initialized
    module" on the other, still mid-initialization. app/api/cgm_connect.py
    imports libre_service directly (deferred, inside connect_libre) without
    ever touching factory.py first, so that endpoint was the real-world
    trigger.

    A plain `import app.services.cgm.libre_service` in this test process
    would NOT actually catch a regression here: by the time this test
    module runs, something else in the suite has almost certainly already
    imported both app.services.cgm.factory and .libre_service, so they're
    already sitting in sys.modules fully initialized regardless of import
    order — the bug is only observable on a genuinely cold interpreter, the
    same way it only surfaced in production on a fresh worker process. A
    subprocess is the one way to reproduce that honestly, mirroring exactly
    what connect_libre's import path does: import libre_service first, with
    nothing else from app.services.cgm loaded yet.
    """
    backend_dir = Path(__file__).resolve().parent.parent
    result = subprocess.run(
        [sys.executable, "-c", "from app.services.cgm.libre_service import LibreCGMService"],
        cwd=backend_dir,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Importing libre_service directly (not via factory) failed:\n{result.stderr}"
    )


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


# ── validate_credentials (connect-time) ──────────────────────────────────────
#
# Regression coverage for a real production bug: an account confirmed
# working in Abbott's own app — login succeeds, authTicket received — still
# came back from connect_libre as connected:false with "Abbott's servers are
# temporarily unavailable", and no cgm_devices row was saved. That message
# only comes from the non-401 branch of validate_credentials' outer
# `except httpx.HTTPStatusError`, meaning the failure was actually in the
# POST-login /llu/connections call, not the login itself — a case none of
# the tests above (which only exercise the on-demand fetch path, not
# validate_credentials) covered at all before this.

def _patch_async_client(monkeypatch, handler):
    """validate_credentials constructs its own httpx.AsyncClient internally
    (unlike _fetch_reading, which goes through the injectable self._client
    seam) — patch the module's httpx.AsyncClient reference so it hands back
    one wired to a MockTransport instead of making real requests.

    `libre_service_mod.httpx` IS the same module object as the `httpx`
    imported at the top of this file (module imports are singletons), so the
    real AsyncClient class must be captured *before* patching — otherwise
    the replacement calls itself forever.
    """
    import app.services.cgm.libre_service as libre_service_mod
    real_async_client = httpx.AsyncClient

    def _fake_client(*args, **kwargs):
        return real_async_client(transport=httpx.MockTransport(handler))

    monkeypatch.setattr(libre_service_mod.httpx, "AsyncClient", _fake_client)


def _login_ok_response() -> httpx.Response:
    return httpx.Response(200, json={"data": {"authTicket": {"token": "tok"}}})


async def test_validate_credentials_maps_non_401_connections_error_to_service_unavailable(monkeypatch):
    """The exact bug: login succeeds, /llu/connections comes back non-401 —
    must map to SERVICE_UNAVAILABLE (the real reason), not silently succeed
    or get mislabeled as invalid credentials."""
    def handler(request: httpx.Request) -> httpx.Response:
        if "/llu/auth/login" in request.url.path:
            return _login_ok_response()
        if "/llu/connections" in request.url.path:
            return httpx.Response(503, json={"error": "abbott outage"})
        return httpx.Response(404)

    _patch_async_client(monkeypatch, handler)
    result = await LibreCGMService().validate_credentials("user@example.com", "pw")

    assert result.success is False
    assert result.error_code == "SERVICE_UNAVAILABLE"


async def test_validate_credentials_maps_401_connections_error_to_invalid_credentials(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        if "/llu/auth/login" in request.url.path:
            return _login_ok_response()
        if "/llu/connections" in request.url.path:
            return httpx.Response(401)
        return httpx.Response(404)

    _patch_async_client(monkeypatch, handler)
    result = await LibreCGMService().validate_credentials("user@example.com", "pw")

    assert result.success is False
    assert result.error_code == "INVALID_CREDENTIALS"


async def test_validate_credentials_reports_connections_not_enabled(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        if "/llu/auth/login" in request.url.path:
            return _login_ok_response()
        if "/llu/connections" in request.url.path:
            return httpx.Response(200, json={"data": []})
        return httpx.Response(404)

    _patch_async_client(monkeypatch, handler)
    result = await LibreCGMService().validate_credentials("user@example.com", "pw")

    assert result.success is False
    assert result.error_code == "CONNECTIONS_NOT_ENABLED"


async def test_validate_credentials_succeeds_with_two_connections_using_the_first(monkeypatch, caplog):
    """Doesn't fix connections[0]-picks-arbitrarily (deferred until real
    account data shows whether it's ever actually the wrong one — see the
    TEMPORARY logging in libre_client.get_connections) but proves it doesn't
    crash or fail validation when Abbott returns more than one, and that the
    multi-connection case gets logged rather than silently picked."""
    two_connections = [
        {"patientId": "p1", "device": {"dtid": 40068}, "sensor": {"a": 1700000000}},
        {"patientId": "p2", "device": {"dtid": 40075}, "sensor": {"a": 1700000000}},
    ]

    def handler(request: httpx.Request) -> httpx.Response:
        if "/llu/auth/login" in request.url.path:
            return _login_ok_response()
        if "/llu/connections" in request.url.path:
            return httpx.Response(200, json={"data": two_connections})
        return httpx.Response(404)

    _patch_async_client(monkeypatch, handler)
    with caplog.at_level("WARNING"):
        result = await LibreCGMService().validate_credentials("user@example.com", "pw")

    assert result.success is True
    assert "account has 2 connections" in caplog.text
    assert "using connections[0] of 2" in caplog.text
