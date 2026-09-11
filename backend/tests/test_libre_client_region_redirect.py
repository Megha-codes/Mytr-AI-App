"""Regression tests for the CGM-connect-rejects-valid-credentials bug:
authenticate_any_region used to treat Abbott's "wrong region, try this one
instead" response (HTTP 200, body {"data": {"redirect": true, "region": ...}})
identically to an outright failure — it has no "authTicket" key, so the old
code's blind `resp.json()["data"]["authTicket"]["token"]` raised a KeyError
that the blanket `except Exception: continue` silently swallowed, moving on
to the next hardcoded region instead of following Abbott's own redirect.
A real account whose home region only reveals itself via this redirect
could exhaust all six hardcoded bases and be reported as invalid credentials
even with a password confirmed correct in Abbott's own app.

Also covers email normalization: a real account can be rejected by a
case/whitespace mismatch alone (a mobile keyboard's autocapitalize is enough
to introduce one), independent of whether the password is right.
"""

from __future__ import annotations

import httpx
import pytest

from app.services.cgm.libre_client import LIBRE_BASES, authenticate_any_region


async def test_redirect_response_is_followed_to_the_indicated_region():
    seen_bases = []

    def handler(request: httpx.Request) -> httpx.Response:
        base = f"{request.url.scheme}://{request.url.host}"
        seen_bases.append(base)
        if base == "https://api.libreview.io":
            # Abbott's real shape for "this account lives elsewhere" —
            # HTTP 200, no authTicket, just a redirect + region code.
            return httpx.Response(200, json={"data": {"redirect": True, "region": "de"}})
        if base == "https://api-de.libreview.io":
            return httpx.Response(200, json={"data": {"authTicket": {"token": "real-tok"}}})
        return httpx.Response(200, json={"data": {"redirect": True, "region": "de"}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await authenticate_any_region(client, "user@example.com", "pw")

    assert result == ("real-tok", "https://api-de.libreview.io")
    # The redirect must be followed immediately, not require exhausting the
    # rest of the fixed region list first.
    assert seen_bases[0] == "https://api.libreview.io"
    assert seen_bases[1] == "https://api-de.libreview.io"


async def test_redirect_loop_gives_up_instead_of_hanging():
    def handler(request: httpx.Request) -> httpx.Response:
        # Every region redirects back to the same one — must terminate, not
        # loop forever or exhaust the process.
        return httpx.Response(200, json={"data": {"redirect": True, "region": "eu"}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await authenticate_any_region(client, "user@example.com", "pw")

    assert result is None


async def test_200_with_neither_token_nor_redirect_is_a_clean_failure():
    # Abbott's real behavior for actually-wrong credentials: HTTP 200 with
    # a body-level error, not a 401. Must not raise, must not be mistaken
    # for a redirect.
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"status": 2, "error": {"message": "bad credentials"}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await authenticate_any_region(client, "user@example.com", "pw")

    assert result is None


@pytest.mark.parametrize("raw_email", [
    "  User@Example.COM  ",
    "USER@EXAMPLE.COM",
    "user@example.com\t",
])
async def test_email_is_trimmed_and_lowercased_before_sending(raw_email):
    sent_emails = []

    def handler(request: httpx.Request) -> httpx.Response:
        import json
        sent_emails.append(json.loads(request.content)["email"])
        return httpx.Response(200, json={"data": {"authTicket": {"token": "tok"}}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await authenticate_any_region(client, raw_email, "pw")

    assert result is not None
    assert sent_emails[0] == "user@example.com"


async def test_first_region_success_does_not_scan_the_rest():
    seen_bases = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen_bases.append(f"{request.url.scheme}://{request.url.host}")
        return httpx.Response(200, json={"data": {"authTicket": {"token": "tok"}}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await authenticate_any_region(client, "user@example.com", "pw")

    assert result == ("tok", LIBRE_BASES[0])
    assert seen_bases == [LIBRE_BASES[0]]
