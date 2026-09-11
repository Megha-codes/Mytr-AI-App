"""Low-level LibreLinkUp (LLU) HTTP client: region scanning, auth, and the
graph-data fetch. Shared by `LibreCGMService` (on-demand, per-request fetch
used by `validate_credentials` at connect-time) and `LibreIngestionService`
(the 24/7 shared poller, architecture-v3.md §4.3) so the request mechanics —
headers, region list, endpoint paths — live in exactly one place.

Correct headers per architecture-v3.md §4.3 step 2 / §5.2: `version 4.16.0`
plus `accept-encoding`/`cache-control`/`connection`. The values for the
latter three match the standard LibreLinkUp Android client headers used
throughout the LibreLinkUp community client implementations (the source
`mytr-desk/docs/data-format.md` lives in a separate repo not present here).
An older, incomplete `version 4.7.0` header set was previously duplicated
directly in this module — see git history — and is wrong.
"""

from __future__ import annotations

import hashlib
import logging
from typing import Optional

import httpx

logger = logging.getLogger("mytr.libre_client")

LIBRE_BASES = [
    "https://api.libreview.io",      # US / Global
    "https://api-eu.libreview.io",   # Europe
    "https://api-de.libreview.io",   # Germany
    "https://api-jp.libreview.io",   # Japan
    "https://api-au.libreview.io",   # Australia
    "https://api-ae.libreview.io",   # Middle East
]

LLU_HEADERS = {
    "product": "llu.android",
    "version": "4.16.0",
    "accept-encoding": "gzip",
    "cache-control": "no-cache",
    "connection": "Keep-Alive",
}

# Max times to follow Abbott's own region-redirect signal for one login
# attempt (see _login_once) before giving up on that email — a safety cap,
# not a real expectation of long chains; Abbott's redirect should resolve
# in one hop.
_MAX_REDIRECT_HOPS = 3


def account_id_header(user_id: str) -> str:
    """Abbott requires an `Account-Id` header — SHA-256 hex digest of the
    logged-in user's id (from the login response's data.user.id) — on every
    authenticated call AFTER login (/llu/connections, /llu/connections/{id}/
    graph). Confirmed directly from a real production failure: login
    succeeded (200, authTicket present) but the very next call,
    /llu/connections, came back 400 {"message": "RequiredHeaderMissing"} —
    this header, entirely absent before, is what was missing. Matches every
    actively-maintained community LibreLinkUp client (libre-link-up-api-
    client, pylibrelinkup, and the Home Assistant LibreLinkUp integrations
    all compute this the same way); not something Abbott documents
    officially anywhere.
    """
    return hashlib.sha256(user_id.encode()).hexdigest()


def _region_base_from_code(region: str) -> str:
    """Abbott's redirect payload gives a bare region code ("de", "us", ...),
    not a full host — map it onto our base-URL naming, defaulting to the
    global host for "us"/unrecognised codes rather than guessing a URL that
    doesn't exist."""
    region = (region or "").lower()
    if region in ("us", "global", ""):
        return "https://api.libreview.io"
    candidate = f"https://api-{region}.libreview.io"
    return candidate


async def _login_once(
    client: httpx.AsyncClient, base: str, email: str, password: str
) -> Optional[tuple[str, str, Optional[str]]]:
    """One login POST against a single region base. Returns (token, base,
    account_id) on success — account_id is the raw data.user.id from
    Abbott's response (None if that field is ever absent; callers must
    treat a missing account_id as "can't call anything past login", not
    silently omit the header it's needed for) — or None on failure,
    including when Abbott's own response says "wrong region, try this one
    instead" (data.redirect), which is handled here by following the
    redirect immediately (bounded by _MAX_REDIRECT_HOPS) rather than
    falling through to the caller's fixed region list, since the redirect
    target is authoritative and may not even be one of our six hardcoded
    bases in the order the caller would otherwise try them.

    TEMPORARY: logs Abbott's actual response (status + body) for every
    attempt, since a login that Abbott's own app accepts but this client
    doesn't needs to be diagnosed against the real response shape rather
    than guessed at — remove once the CGM-connect-rejects-valid-credentials
    issue is confirmed fixed. Never logs the password.
    """
    visited = set()
    current_base = base

    for _ in range(_MAX_REDIRECT_HOPS):
        if current_base in visited:
            logger.warning(
                "libre_client: redirect loop detected (base=%s already tried), aborting this chain",
                current_base,
            )
            return None
        visited.add(current_base)

        try:
            resp = await client.post(
                f"{current_base}/llu/auth/login",
                json={"email": email, "password": password},
                headers=LLU_HEADERS,
            )
        except Exception as exc:
            logger.warning("libre_client: request to %s failed: %s", current_base, exc)
            return None

        # TEMPORARY diagnostic logging — status + body only, password never
        # included (it's only ever in the outgoing request, not logged here).
        try:
            body_for_log = resp.json()
        except Exception:
            body_for_log = resp.text[:500]
        logger.warning(
            "libre_client: login attempt base=%s status=%s body=%s",
            current_base, resp.status_code, body_for_log,
        )

        if resp.status_code != 200:
            return None

        data = resp.json().get("data", {})

        auth_ticket = data.get("authTicket")
        if auth_ticket and auth_ticket.get("token"):
            account_id = (data.get("user") or {}).get("id")
            if not account_id:
                logger.warning(
                    "libre_client: login succeeded but data.user.id is missing — "
                    "Account-Id header can't be computed, subsequent calls will fail"
                )
            return auth_ticket["token"], current_base, account_id

        if data.get("redirect"):
            next_base = _region_base_from_code(data.get("region", ""))
            logger.warning(
                "libre_client: Abbott redirected base=%s -> region=%s (%s)",
                current_base, data.get("region"), next_base,
            )
            current_base = next_base
            continue

        # 200 with neither a token nor a redirect — Abbott's body-level
        # status/error (LibreView returns HTTP 200 for many application-level
        # errors, e.g. bad credentials, with the real outcome in the JSON
        # body) is what the diagnostic log line above will show.
        return None

    logger.warning("libre_client: exceeded %d redirect hops, giving up", _MAX_REDIRECT_HOPS)
    return None


async def authenticate_any_region(
    client: httpx.AsyncClient,
    email: str,
    password: str,
    preferred_region: Optional[str] = None,
) -> Optional[tuple[str, str, Optional[str]]]:
    """Log in, scanning regions until one accepts the credentials.

    Returns (token, region_base, account_id) — account_id must be passed to
    get_connections/get_graph_data as the Account-Id header they require
    post-login (see account_id_header).

    `preferred_region` (the durably-cached region_base from a prior
    successful login) is tried first so a restarted poller doesn't have to
    re-scan all six hosts before its first successful poll.

    Email is trimmed and lowercased before sending — Abbott's login treats
    the account email case-insensitively (matching every community
    LibreLinkUp API client's normalization), and a mobile keyboard's
    autocapitalize/autocomplete can easily hand this function a differently-
    cased or whitespace-padded value than what's registered, causing a
    real, working account to be rejected for a reason that has nothing to
    do with the password being wrong.
    """
    email = email.strip().lower()

    ordered_bases = LIBRE_BASES
    if preferred_region and preferred_region in LIBRE_BASES:
        ordered_bases = [preferred_region] + [b for b in LIBRE_BASES if b != preferred_region]

    for base in ordered_bases:
        result = await _login_once(client, base, email, password)
        if result is not None:
            return result
    return None


def _log_response(label: str, base: str, resp: httpx.Response) -> None:
    # TEMPORARY diagnostic logging — see _login_once's docstring. Same
    # reasoning applies here: the post-login /llu/connections call is where
    # a real, Abbott-confirmed-correct login has been observed to still end
    # up reported as "temporarily unavailable" (a non-401 HTTPStatusError
    # from this call, or the /graph call below, being caught generically
    # upstream with no record of what Abbott actually said). Never logs the
    # bearer token or any credential.
    try:
        body_for_log = resp.json()
    except Exception:
        body_for_log = resp.text[:500]
    logger.warning(
        "libre_client: %s base=%s status=%s body=%s",
        label, base, resp.status_code, body_for_log,
    )


async def get_connections(
    client: httpx.AsyncClient, base: str, token: str, account_id: Optional[str] = None
) -> list:
    headers = {**LLU_HEADERS, "Authorization": f"Bearer {token}"}
    if account_id:
        headers["Account-Id"] = account_id_header(account_id)
    resp = await client.get(f"{base}/llu/connections", headers=headers)
    _log_response("connections", base, resp)
    resp.raise_for_status()
    data = resp.json().get("data", [])
    # TEMPORARY: an account with more than one connection (e.g. a sensor
    # swap in progress, old sensor still reporting alongside the new one)
    # picks connections[0] unconditionally in libre_service.py — logging
    # the full list here so we can see, from real data, whether that's ever
    # actually wrong rather than guessing at a fix.
    if len(data) > 1:
        logger.warning(
            "libre_client: account has %d connections, callers currently use only the first: %s",
            len(data), data,
        )
    return data


async def get_graph_data(
    client: httpx.AsyncClient, base: str, token: str, patient_id: str, account_id: Optional[str] = None
) -> list:
    headers = {**LLU_HEADERS, "Authorization": f"Bearer {token}"}
    if account_id:
        headers["Account-Id"] = account_id_header(account_id)
    resp = await client.get(f"{base}/llu/connections/{patient_id}/graph", headers=headers)
    _log_response("graph", base, resp)
    resp.raise_for_status()
    return resp.json()["data"]["graphData"]
