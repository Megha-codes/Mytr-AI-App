"""Startup/shutdown wiring for the device pipeline (poller + store + hub).

Shared by the main app (app/main.py) and the isolated proof app
(app/device_app.py) so both stand the schema up and run the in-process Libre
poller the same way. The poller only starts when it's explicitly enabled and
credentials are present, so importing the app never begins hitting Abbott.
"""

from __future__ import annotations

import asyncio
import logging

from .core.config import settings
from .device_database import init_device_schema
from .services.device_hub import hub
from .services.device_store import store
from .services.libre_poller import LibrePoller

logger = logging.getLogger("mytr.device_runtime")

_poller_task: asyncio.Task | None = None


async def start_device_pipeline() -> None:
    """Create device tables and, if enabled, launch the background poller."""
    global _poller_task

    await init_device_schema()

    if not settings.LIBRE_POLLER_ENABLED:
        logger.info("Libre poller disabled (LIBRE_POLLER_ENABLED not set).")
        return
    if not settings.LIBRE_EMAIL or not settings.LIBRE_PASSWORD:
        logger.warning("Libre poller enabled but LIBRE_EMAIL/LIBRE_PASSWORD unset; not starting.")
        return

    poller = LibrePoller(
        store,
        hub,
        region=settings.LIBRE_REGION,
        email=settings.LIBRE_EMAIL,
        password=settings.LIBRE_PASSWORD,
        tz_name=settings.LIBRE_ACCOUNT_TIMEZONE or None,
        interval_s=settings.LIBRE_POLL_INTERVAL_S,
        base_url=settings.LIBRE_BASE_URL or None,
    )
    _poller_task = asyncio.create_task(poller.run_forever())


async def stop_device_pipeline() -> None:
    global _poller_task
    if _poller_task is not None:
        _poller_task.cancel()
        try:
            await _poller_task
        except asyncio.CancelledError:
            pass
        _poller_task = None
