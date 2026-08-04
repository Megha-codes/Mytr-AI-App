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

from typing import Optional

import httpx

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


async def authenticate_any_region(
    client: httpx.AsyncClient,
    email: str,
    password: str,
    preferred_region: Optional[str] = None,
) -> Optional[tuple[str, str]]:
    """Log in, scanning regions until one accepts the credentials.

    `preferred_region` (the durably-cached region_base from a prior
    successful login) is tried first so a restarted poller doesn't have to
    re-scan all six hosts before its first successful poll.
    """
    ordered_bases = LIBRE_BASES
    if preferred_region and preferred_region in LIBRE_BASES:
        ordered_bases = [preferred_region] + [b for b in LIBRE_BASES if b != preferred_region]

    for base in ordered_bases:
        try:
            resp = await client.post(
                f"{base}/llu/auth/login",
                json={"email": email, "password": password},
                headers=LLU_HEADERS,
            )
            if resp.status_code == 200:
                return resp.json()["data"]["authTicket"]["token"], base
        except Exception:
            continue
    return None


async def get_connections(client: httpx.AsyncClient, base: str, token: str) -> list:
    resp = await client.get(
        f"{base}/llu/connections",
        headers={**LLU_HEADERS, "Authorization": f"Bearer {token}"},
    )
    resp.raise_for_status()
    return resp.json().get("data", [])


async def get_graph_data(client: httpx.AsyncClient, base: str, token: str, patient_id: str) -> list:
    resp = await client.get(
        f"{base}/llu/connections/{patient_id}/graph",
        headers={**LLU_HEADERS, "Authorization": f"Bearer {token}"},
    )
    resp.raise_for_status()
    return resp.json()["data"]["graphData"]
