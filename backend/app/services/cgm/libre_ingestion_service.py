"""LibreIngestionService: the shared 24/7 Libre poller (architecture-v3.md
§4.3). One poll loop per distinct Libre account (deduped by credentials),
running independent of any client connection, writing directly into
TimescaleDB with `ON CONFLICT DO NOTHING` against the dedup index.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional

import httpx
from sqlalchemy import select, text
from sqlalchemy.dialects import postgresql, sqlite
from sqlalchemy.ext.asyncio import AsyncSession

from ...database import AsyncSessionLocal
from ...models.glucose_reading import GlucoseReadingModel
from ...models.user import CGMDevice
from ...services.realtime.fanout_hub import FanoutHub, fanout_hub as default_fanout_hub
from ...timescale_database import TimescaleSessionLocal
from ..libre_timestamp import libre_timestamp_to_epoch
from .libre_account_registry import EligibleAccount, get_eligible_accounts, group_by_credential
from .libre_client import authenticate_any_region, get_connections, get_graph_data

logger = logging.getLogger("mytr.libre_ingestion")

_TREND_MAP = {
    1: ("FALLING_FAST", "↓↓"),
    2: ("FALLING", "↓"),
    3: ("STABLE", "→"),
    4: ("RISING", "↑"),
    5: ("RISING_FAST", "↑↑"),
}

POLL_INTERVAL_SECONDS = 60
REGISTRY_REFRESH_SECONDS = 300


def _insert_builder(dialect_name: str):
    # Production runs on Postgres; sqlite is a test-only stand-in (see
    # tests/conftest.py). Both dialects support the same
    # insert(...).on_conflict_do_nothing(index_elements=..., index_where=...)
    # surface, so this is the only place that needs to know which is live.
    return sqlite.insert if dialect_name == "sqlite" else postgresql.insert


def _resolve_sensor_id(connection: dict) -> str:
    """The dedup key. Prefer the physical sensor serial; fall back to the
    patientId (stable per Libre account) if the API shape doesn't expose it,
    so ingestion is never accidentally left un-deduplicated."""
    sensor = connection.get("sensor") or {}
    return sensor.get("sn") or connection.get("patientId") or "unknown"


class LibreIngestionService:
    def __init__(
        self,
        db_session_factory=None,
        timescale_session_factory=None,
        poll_interval_seconds: float = POLL_INTERVAL_SECONDS,
        registry_refresh_seconds: float = REGISTRY_REFRESH_SECONDS,
        fanout_hub: Optional[FanoutHub] = None,
    ) -> None:
        self._db_session_factory = db_session_factory or AsyncSessionLocal
        self._timescale_session_factory = timescale_session_factory or TimescaleSessionLocal
        self._poll_interval_seconds = poll_interval_seconds
        self._registry_refresh_seconds = registry_refresh_seconds
        self._fanout_hub = fanout_hub or default_fanout_hub

        # In-process cache: email -> (token, region_base). The durable half
        # of this (region_base surviving a restart) lives in
        # cgm_devices.region_base — see _load_cached_region/_persist_region.
        self._sessions: dict[str, tuple[Optional[str], Optional[str]]] = {}
        self._tasks: dict[str, asyncio.Task] = {}
        self._stopped = asyncio.Event()

    def _client(self) -> httpx.AsyncClient:
        # Small seam so tests can inject an httpx.MockTransport, mirroring
        # LibreCGMService's own `_client()` seam.
        return httpx.AsyncClient(timeout=15.0)

    # ── Lifecycle ────────────────────────────────────────────────────────────

    async def run_forever(self) -> None:
        """Refreshes the account registry on an interval, starting/stopping
        one background poll task per distinct Libre account as eligibility
        changes. Runs until `stop()` is called."""
        while not self._stopped.is_set():
            try:
                await self.refresh_loops()
            except Exception:
                logger.exception("Libre ingestion registry refresh failed")
            try:
                await asyncio.wait_for(
                    self._stopped.wait(), timeout=self._registry_refresh_seconds
                )
            except asyncio.TimeoutError:
                pass

    async def stop(self) -> None:
        self._stopped.set()
        for task in self._tasks.values():
            task.cancel()
        if self._tasks:
            await asyncio.gather(*self._tasks.values(), return_exceptions=True)
        self._tasks.clear()

    async def refresh_loops(self) -> None:
        """Starts a poll task for every newly-eligible Libre account and
        cancels tasks for accounts that dropped out of eligibility (Libre
        disconnected, device unpaired with no recent session, etc.)."""
        async with self._db_session_factory() as db:
            accounts = await get_eligible_accounts(db)
        groups = group_by_credential(accounts)

        for email in list(self._tasks):
            if email not in groups:
                self._tasks[email].cancel()
                del self._tasks[email]

        for email, group_accounts in groups.items():
            existing = self._tasks.get(email)
            if existing is None or existing.done():
                self._tasks[email] = asyncio.create_task(self._poll_loop(email, group_accounts))

    async def _poll_loop(self, email: str, accounts: list[EligibleAccount]) -> None:
        while True:
            try:
                await self.poll_account_once(email, accounts)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Libre poll failed for account")
            await asyncio.sleep(self._poll_interval_seconds)

    # ── One fetch+ingest cycle — the testable unit ──────────────────────────

    async def poll_account_once(self, email: str, accounts: list[EligibleAccount]) -> int:
        """One login-if-needed + connections + graph fetch, fanned out to
        every mytr.ai user sharing this Libre login (one Abbott round trip,
        N DB writes). Returns a best-effort count of rows actually written —
        for observability only; tests should assert real row counts."""
        password = accounts[0].password
        token, region_base = self._sessions.get(email, (None, None))

        async with self._client() as client:
            if token is None:
                if region_base is None:
                    region_base = await self._load_cached_region(accounts)
                auth = await authenticate_any_region(
                    client, email, password, preferred_region=region_base
                )
                if auth is None:
                    logger.warning("Libre login failed (region scan exhausted)")
                    return 0
                token, region_base = auth
                self._sessions[email] = (token, region_base)
                await self._persist_region(accounts, region_base)

            try:
                connections = await get_connections(client, region_base, token)
            except httpx.HTTPStatusError as exc:
                if exc.response.status_code != 401:
                    raise
                # Cached token expired — drop it, re-login once, retry.
                auth = await authenticate_any_region(
                    client, email, password, preferred_region=region_base
                )
                if auth is None:
                    self._sessions.pop(email, None)
                    return 0
                token, region_base = auth
                self._sessions[email] = (token, region_base)
                await self._persist_region(accounts, region_base)
                connections = await get_connections(client, region_base, token)

            if not connections:
                return 0

            connection = connections[0]
            patient_id = connection["patientId"]
            sensor_id = _resolve_sensor_id(connection)
            graph_data = await get_graph_data(client, region_base, token, patient_id)

        written = 0
        async with self._timescale_session_factory() as ts_db:
            insert = _insert_builder(ts_db.bind.dialect.name)
            for account in accounts:
                written += await self._ingest_account(ts_db, insert, account, sensor_id, graph_data)
            await ts_db.commit()
        return written

    async def _ingest_account(
        self,
        ts_db: AsyncSession,
        insert,
        account: EligibleAccount,
        sensor_id: str,
        graph_data: list,
    ) -> int:
        written = 0
        for item in graph_data:
            raw_ts = item.get("Timestamp")
            if not raw_ts:
                continue
            try:
                # Per-user timezone (architecture-v3.md §4.3 step 3) — not
                # the global LIBRE_ACCOUNT_TIMEZONE setting, since a shared
                # poller serves many accounts across different zones.
                epoch = libre_timestamp_to_epoch(raw_ts, account.timezone)
            except ValueError:
                continue
            recorded_at = datetime.fromtimestamp(epoch, tz=timezone.utc)
            trend_code = item.get("TrendArrow", 3)
            trend, trend_arrow = _TREND_MAP.get(trend_code, ("STABLE", "→"))
            value = int(item.get("ValueInMgPerDl") or item.get("Value", 0))
            stmt = (
                insert(GlucoseReadingModel)
                .values(
                    user_id=account.user_id,
                    value_mgdl=value,
                    trend=trend,
                    trend_arrow=trend_arrow,
                    device_type="LIBRE",
                    is_continuous=True,
                    recorded_at=recorded_at,
                    sensor_id=sensor_id,
                    source="LIBRE",
                )
                .on_conflict_do_nothing(
                    index_elements=["user_id", "sensor_id", "recorded_at"],
                    index_where=text("sensor_id IS NOT NULL"),
                )
                # `rowcount` on an ON CONFLICT DO NOTHING insert isn't a
                # reliable "did this actually insert" signal across drivers
                # once a server_default column (id) is involved — RETURNING
                # is: it yields a row iff the insert wasn't skipped, on both
                # Postgres and the sqlite test backend.
                .returning(GlucoseReadingModel.id)
            )
            result = await ts_db.execute(stmt)
            newly_inserted = result.first() is not None
            written += int(newly_inserted)

            # Only publish for readings actually written this cycle — the
            # poller re-fetches overlapping graph windows every poll, so
            # without this check every already-seen reading would be
            # re-published (and re-delivered to every live subscriber) on
            # every single poll interval.
            if newly_inserted:
                self._fanout_hub.publish_glucose_reading(
                    account.user_id, recorded_at=recorded_at, mgdl=value,
                    trend=trend, trend_arrow=trend_arrow, sensor_id=sensor_id,
                    source="LIBRE",
                )
                self._fanout_hub.publish_glucose_state(
                    account.user_id, state="LIVE", since=recorded_at,
                )
        return written

    # ── Durable region persistence (§4.3 step 3) ────────────────────────────

    async def _load_cached_region(self, accounts: list[EligibleAccount]) -> Optional[str]:
        async with self._db_session_factory() as db:
            for account in accounts:
                result = await db.execute(
                    select(CGMDevice.region_base).where(CGMDevice.id == account.cgm_device_id)
                )
                region = result.scalar_one_or_none()
                if region:
                    return region
        return None

    async def _persist_region(self, accounts: list[EligibleAccount], region_base: str) -> None:
        async with self._db_session_factory() as db:
            for account in accounts:
                result = await db.execute(
                    select(CGMDevice).where(CGMDevice.id == account.cgm_device_id)
                )
                cgm_device = result.scalar_one_or_none()
                if cgm_device is not None and cgm_device.region_base != region_base:
                    cgm_device.region_base = region_base
            await db.commit()
