"""LibreLinkUp poller for the mytr-desk device pipeline.

Server-side port of cgm-pipeline/lib/services/libre_link_service.dart: it logs
in to LibreLinkUp, lists connections, pulls each patient's ~12h graph, and
normalizes every reading into the wire shape syncd consumes
(``{"ts", "mgdl", "trend", "sensor_id"}``) before writing it to the device
store and publishing it to connected stream clients.

Two things are load-bearing and easy to get wrong, so they live in small pure
functions with their own tests:

- ``map_trend_arrow`` — LibreLinkUp's 1-5 ``TrendArrow`` -> our string label.
- ``libre_timestamp_to_epoch`` — the US-style, timezone-less ``Timestamp``
  string ("6/9/2024 3:45:12 PM") resolved against the account timezone and
  converted to a UTC unix-epoch integer. This ambiguity is resolved **once,
  here**, so a raw Libre timestamp string never reaches the device.

Credentials come from Settings (loaded from .env) and are never logged.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import re
from datetime import datetime, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx

logger = logging.getLogger("mytr.libre_poller")

# Exact headers the real LibreLinkUp app sends. Abbott silently rejects or
# redirects requests missing accept-encoding / cache-control / connection, or
# carrying a stale `version`, so these are not optional.
_BASE_HEADERS = {
    "accept-encoding": "gzip",
    "cache-control": "no-cache",
    "connection": "Keep-Alive",
    "content-type": "application/json",
    "product": "llu.android",
    "version": "4.16.0",
}

_REGION_HOSTS = {
    "us": "api-us.libreview.io",
    "eu": "api-eu.libreview.io",
    "de": "api-de.libreview.io",
    "fr": "api-fr.libreview.io",
    "jp": "api-jp.libreview.io",
    "ap": "api-ap.libreview.io",
    "au": "api-au.libreview.io",
    "ca": "api-ca.libreview.io",
}

# LibreLinkUp TrendArrow (1-5) -> mytr-desk's own string trend label
# (device/schema.sql). Missing / non-int defaults to steady == "flat", the
# same default the Flutter reference client uses.
_TREND_LABELS = {
    1: "falling_rapid",  # falling fast
    2: "falling",
    3: "flat",           # steady
    4: "rising",
    5: "rising_rapid",   # rising fast
}

_TIMESTAMP_RE = re.compile(
    r"^(\d{1,2})/(\d{1,2})/(\d{4}) (\d{1,2}):(\d{2}):(\d{2}) ?(AM|PM)$",
    re.IGNORECASE,
)


class LibrePollerError(Exception):
    """Raised for login/region/terms failures returned by LibreLinkUp."""


# ── Pure normalization helpers (unit-tested) ──────────────────────────────────

def map_trend_arrow(code: object) -> str:
    """Map a LibreLinkUp TrendArrow code (1-5) to a mytr-desk trend label.

    Anything missing or not an int in 1-5 falls back to "flat" (steady).
    """
    if isinstance(code, bool):  # bool is an int subclass — reject it explicitly
        return "flat"
    if isinstance(code, int):
        return _TREND_LABELS.get(code, "flat")
    return "flat"


def parse_libre_timestamp(raw: str) -> datetime:
    """Parse a US-style, timezone-less Libre timestamp into a *naive* datetime.

    Format: ``M/D/YYYY H:MM:SS AM/PM`` e.g. "6/9/2024 3:45:12 PM". No timezone
    is attached here — the caller must resolve that (see
    ``libre_timestamp_to_epoch``). Raises ``ValueError`` if the string doesn't
    match, so a format change surfaces loudly instead of being silently
    mis-stored.
    """
    match = _TIMESTAMP_RE.match(raw.strip())
    if match is None:
        # Last-ditch: maybe Abbott switched to ISO-8601. Let fromisoformat try;
        # if that also fails it raises ValueError, which is what we want.
        return datetime.fromisoformat(raw.strip()).replace(tzinfo=None)

    month, day, year, hour, minute, second = (int(match.group(i)) for i in range(1, 7))
    meridiem = match.group(7).upper()
    if meridiem == "PM" and hour != 12:
        hour += 12
    elif meridiem == "AM" and hour == 12:
        hour = 0
    return datetime(year, month, day, hour, minute, second)


def _resolve_zone(tz_name: str | None) -> timezone | ZoneInfo:
    if not tz_name:
        logger.warning(
            "No LIBRE_ACCOUNT_TIMEZONE set; interpreting naive Libre timestamps "
            "as UTC. Set the account's IANA timezone for correct conversion."
        )
        return timezone.utc
    try:
        return ZoneInfo(tz_name)
    except (ZoneInfoNotFoundError, ValueError):
        logger.warning("Unknown timezone %r; falling back to UTC.", tz_name)
        return timezone.utc


def libre_timestamp_to_epoch(raw: str, tz_name: str | None) -> int:
    """Convert a naive US-style Libre timestamp to a UTC unix-epoch integer.

    ``tz_name`` is the IANA timezone the account's timestamps are expressed in
    (e.g. "Asia/Kolkata"). The naive wall-clock time is localized to that zone
    and then converted to UTC, so the returned epoch is unambiguous regardless
    of where the backend itself runs.
    """
    naive = parse_libre_timestamp(raw)
    localized = naive.replace(tzinfo=_resolve_zone(tz_name))
    return int(localized.astimezone(timezone.utc).timestamp())


def account_id_hash(user_id: str) -> str:
    """SHA-256 hex of the LibreLinkUp user id, sent as the account-id header."""
    return hashlib.sha256(user_id.encode("utf-8")).hexdigest()


def normalize_reading(item: dict, sensor_id: str, tz_name: str | None) -> dict:
    """Turn one raw graphData / glucoseMeasurement entry into a wire reading."""
    value = item.get("ValueInMgPerDl")
    if value is None:
        value = item.get("Value", 0)
    return {
        "ts": libre_timestamp_to_epoch(item["Timestamp"], tz_name),
        "mgdl": float(value),
        "trend": map_trend_arrow(item.get("TrendArrow")),
        "sensor_id": sensor_id,
    }


def sensor_id_for(connection: dict) -> str:
    """Best-effort stable sensor identifier for a connection."""
    sensor = connection.get("sensor") or {}
    return str(sensor.get("sn") or connection.get("patientId") or "unknown-sensor")


# ── LibreLinkUp HTTP client ───────────────────────────────────────────────────

class LibreLinkUpClient:
    """Thin async client mirroring the Dart LibreLinkService call sequence.

    Caches the bearer token + account-id hash after login and reuses them
    across polls; ``login`` is only re-run when a call comes back 401.
    """

    def __init__(self, region: str, email: str, password: str,
                 base_url: str | None = None) -> None:
        if base_url:
            # Explicit override (staging proxy, self-hosted gateway, or a test
            # fixture) — takes precedence over the regional host.
            self._base = base_url.rstrip("/")
        else:
            host = _REGION_HOSTS.get(region.lower())
            if host is None:
                raise LibrePollerError(
                    f"Unknown Libre region {region!r}; expected one of {sorted(_REGION_HOSTS)}"
                )
            self._base = f"https://{host}"
        self._email = email
        self._password = password
        self._token: str | None = None
        self._account_id: str | None = None

    @property
    def is_authenticated(self) -> bool:
        return self._token is not None

    def _headers(self) -> dict[str, str]:
        headers = dict(_BASE_HEADERS)
        if self._token:
            headers["authorization"] = f"Bearer {self._token}"
        if self._account_id:
            headers["account-id"] = self._account_id
        return headers

    async def login(self, client: httpx.AsyncClient) -> None:
        resp = await client.post(
            f"{self._base}/llu/auth/login",
            headers=self._headers(),
            json={"email": self._email, "password": self._password},
        )
        if resp.status_code != 200:
            # Never echo the body — it can include the submitted email.
            raise LibrePollerError(f"Login failed (HTTP {resp.status_code})")

        data = resp.json().get("data")
        if isinstance(data, dict) and data.get("redirect") is True:
            raise LibrePollerError(
                f"Wrong region: account belongs to region "
                f"{data.get('region')!r}. Set LIBRE_REGION accordingly."
            )
        step_type = None
        if isinstance(data, dict) and isinstance(data.get("step"), dict):
            step_type = data["step"].get("type")
        if step_type == "tou":
            raise LibrePollerError("Account must accept updated Terms of Use in the LibreLinkUp app.")
        if step_type == "pp":
            raise LibrePollerError("Account must accept updated Privacy Policy in the LibreLinkUp app.")
        if step_type == "verifyEmail":
            raise LibrePollerError("Account email is not verified yet.")

        if not isinstance(data, dict) or not data.get("authTicket"):
            raise LibrePollerError("Login rejected by LibreLinkUp (no authTicket in response).")

        self._token = data["authTicket"]["token"]
        self._account_id = account_id_hash(data["user"]["id"])

    async def get_connections(self, client: httpx.AsyncClient) -> list[dict]:
        resp = await client.get(f"{self._base}/llu/connections", headers=self._headers())
        resp.raise_for_status()
        return resp.json().get("data", []) or []

    async def get_graph(self, client: httpx.AsyncClient, patient_id: str) -> list[dict]:
        resp = await client.get(
            f"{self._base}/llu/connections/{patient_id}/graph",
            headers=self._headers(),
        )
        resp.raise_for_status()
        return resp.json().get("data", {}).get("graphData", []) or []


# ── Poll orchestration ────────────────────────────────────────────────────────

class LibrePoller:
    """Owns the 60s poll loop: fetch -> normalize -> store -> publish."""

    def __init__(self, store, hub, *, region: str, email: str, password: str,
                 tz_name: str | None, interval_s: int = 60,
                 base_url: str | None = None) -> None:
        self._store = store
        self._hub = hub
        self._client = LibreLinkUpClient(region, email, password, base_url=base_url)
        self._tz_name = tz_name
        self._interval_s = interval_s
        self._http: httpx.AsyncClient | None = None

    async def poll_once(self) -> int:
        """Run one fetch cycle. Returns the number of newly-stored readings."""
        assert self._http is not None
        if not self._client.is_authenticated:
            await self._client.login(self._http)

        try:
            connections = await self._client.get_connections(self._http)
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 401:
                # Token expired mid-session — re-login once and retry.
                await self._client.login(self._http)
                connections = await self._client.get_connections(self._http)
            else:
                raise

        readings: list[dict] = []
        for connection in connections:
            patient_id = connection.get("patientId")
            if not patient_id:
                continue
            sensor_id = sensor_id_for(connection)
            graph = await self._client.get_graph(self._http, patient_id)
            for item in graph:
                try:
                    readings.append(normalize_reading(item, sensor_id, self._tz_name))
                except (KeyError, ValueError) as exc:
                    logger.warning("skipping unparseable Libre reading: %s", exc)

        if not readings:
            return 0

        inserted = await self._store.insert_readings(readings)
        for reading in inserted:
            await self._hub.publish(reading)
        if inserted:
            logger.info("poll: %d fetched, %d new", len(readings), len(inserted))
        return len(inserted)

    async def run_forever(self) -> None:
        """Poll every ``interval_s`` seconds until cancelled, surviving errors."""
        self._http = httpx.AsyncClient(timeout=20.0)
        logger.info("Libre poller started (interval=%ds)", self._interval_s)
        try:
            while True:
                try:
                    await self.poll_once()
                except asyncio.CancelledError:
                    raise
                except LibrePollerError as exc:
                    logger.error("Libre poll aborted: %s", exc)
                except Exception:
                    logger.exception("Libre poll cycle failed; will retry")
                await asyncio.sleep(self._interval_s)
        finally:
            await self._http.aclose()
            self._http = None
