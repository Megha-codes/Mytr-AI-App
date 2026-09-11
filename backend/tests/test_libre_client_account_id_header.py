"""Regression test for the actual root cause behind "login succeeds but
connect_libre still reports failure": Abbott requires an `Account-Id`
header (SHA-256 hex digest of the logged-in user's id) on every
authenticated call AFTER login. Confirmed directly from a real production
log — login returned 200 with a real authTicket, and the very next call,
GET /llu/connections, came back 400 {"message": "RequiredHeaderMissing"}.
This header was entirely absent from get_connections/get_graph_data before
this fix; it's undocumented by Abbott but present in every actively-
maintained community LibreLinkUp client.
"""

from __future__ import annotations

import hashlib

import httpx
import pytest

from app.services.cgm.libre_client import account_id_header, get_connections, get_graph_data


def test_account_id_header_is_sha256_of_the_user_id():
    # Pin the exact algorithm, not just "produces something" — this must
    # match what Abbott's servers actually expect, not an arbitrary hash.
    assert account_id_header("uid-123") == hashlib.sha256(b"uid-123").hexdigest()


async def test_get_connections_sends_account_id_header_when_given():
    seen_headers = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen_headers.update(request.headers)
        return httpx.Response(200, json={"data": []})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await get_connections(client, "https://api.libreview.io", "tok", "uid-123")

    assert seen_headers.get("account-id") == hashlib.sha256(b"uid-123").hexdigest()


async def test_get_connections_omits_account_id_header_when_not_given():
    """Backward-compat seam, not a real production path: account_id is
    optional so tests that pre-date this fix (mocked logins without a
    data.user.id in the response) keep working unchanged. A real login
    always has account_id — see _login_once's warning log when it doesn't."""
    seen_headers = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen_headers.update(request.headers)
        return httpx.Response(200, json={"data": []})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await get_connections(client, "https://api.libreview.io", "tok")

    assert "account-id" not in seen_headers


async def test_get_graph_data_sends_account_id_header_when_given():
    seen_headers = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen_headers.update(request.headers)
        return httpx.Response(200, json={"data": {"graphData": []}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await get_graph_data(client, "https://api.libreview.io", "tok", "patient-1", "uid-123")

    assert seen_headers.get("account-id") == hashlib.sha256(b"uid-123").hexdigest()


async def test_reproduces_the_real_production_failure_then_confirms_the_fix():
    """The exact sequence from the production log: login succeeds, then
    /llu/connections 400s with RequiredHeaderMissing when Account-Id is
    absent — and succeeds once it's sent."""
    def handler(request: httpx.Request) -> httpx.Response:
        if "account-id" not in request.headers:
            return httpx.Response(400, json={"message": "RequiredHeaderMissing"})
        return httpx.Response(200, json={"data": [{"patientId": "p1"}]})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(httpx.HTTPStatusError):
            await get_connections(client, "https://api.libreview.io", "tok")  # no account_id -> reproduces the bug

        # Same call, with the header this fix adds -> succeeds.
        result = await get_connections(client, "https://api.libreview.io", "tok", "uid-123")

    assert result == [{"patientId": "p1"}]
