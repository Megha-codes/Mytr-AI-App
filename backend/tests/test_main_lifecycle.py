"""Tests that the shared Libre poller is actually wired into the app
lifecycle (architecture-v3.md §4.3: "running independent of any client
connection" — it has to start on boot, not on first websocket connect).

Doesn't boot the app through TestClient/lifespan: init_timescale_schema()
talks to a real TimescaleDB, unavailable in this offline test environment
(consistent with every other test file in this suite). Instead this calls
the startup/shutdown handlers directly with init_timescale_schema and the
service's run_forever() swapped for cheap stand-ins.
"""

from __future__ import annotations

import asyncio


async def test_startup_launches_ingestion_task_and_shutdown_stops_it(monkeypatch):
    import app.main as main_mod

    async def _noop():
        return None

    async def _fake_run_forever():
        await asyncio.Event().wait()  # runs until cancelled, like the real loop would

    monkeypatch.setattr(main_mod, "init_timescale_schema", _noop)
    monkeypatch.setattr(main_mod.libre_ingestion_service, "run_forever", _fake_run_forever)

    await main_mod.startup()
    try:
        task = main_mod.app.state.libre_ingestion_task
        assert isinstance(task, asyncio.Task)
        assert not task.done()
    finally:
        await main_mod.shutdown()

    assert task.done()
