"""Smoke test for the diagnostic logging added to make the shared Libre
poller's activity visible — previously refresh_loops/_poll_loop only ever
logged on an actual exception, so "the poller isn't doing anything visible"
was indistinguishable from "the poller is silently working correctly" and
from "no account is currently eligible" (not an error at all, just a
`continue` with zero record of why)."""

from __future__ import annotations

from app.services.cgm.libre_ingestion_service import LibreIngestionService

from .conftest import build_sqlite_db


async def test_refresh_loops_logs_a_summary_even_with_zero_eligible_accounts(caplog):
    engine, session_factory = await build_sqlite_db()
    service = LibreIngestionService(db_session_factory=session_factory)

    with caplog.at_level("INFO"):
        await service.refresh_loops()

    assert "registry refresh" in caplog.text
    assert "0 eligible account(s)" in caplog.text
