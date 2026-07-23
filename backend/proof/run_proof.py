"""End-to-end proof for the mytr-desk device pipeline — fully offline.

What it demonstrates, against the *real* backend (not the mock), all in one
process:

  1. Poller -> store: the LibreLinkUp poller logs in to a fake LibreLinkUp,
     pulls readings whose timestamps are US-style, timezone-less strings in
     Asia/Kolkata, and stores them with correctly-parsed **UTC** epochs.

  2. syncd zero-gaps/zero-dupes: syncd's real client/db/reading modules stream
     from this backend, get force-disconnected mid-stream while the poller keeps
     producing readings, reconnect, and backfill — ending with the device's DB
     holding exactly the backend's full set: no gaps, no duplicates. The same
     guarantee the mock server gave.

Run (from backend/, with the venv active):
    python -m proof.run_proof

Swap the fake LibreLinkUp for the real one by filling backend/.env and running
the poller for real — see proof/RUNBOOK.md.
"""

from __future__ import annotations

import asyncio
import os
import sqlite3
import sys
import tempfile
import uuid
from pathlib import Path

# ── Environment: point the backend at a throwaway SQLite store + fake LLU ─────
# Must be set before importing app.* (config/engines read env at import time).
_TMP = Path(tempfile.mkdtemp(prefix="mytr-proof-"))
os.environ["JWT_SECRET"] = "proof-secret-not-real"
os.environ["DEVICE_DATABASE_URL"] = f"sqlite+aiosqlite:///{(_TMP / 'backend.db').as_posix()}"
os.environ["LIBRE_POLLER_ENABLED"] = "true"
os.environ["LIBRE_BASE_URL"] = "http://127.0.0.1:9701"
os.environ["LIBRE_EMAIL"] = "proof@example.com"
os.environ["LIBRE_PASSWORD"] = "proof-password"
os.environ["LIBRE_ACCOUNT_TIMEZONE"] = "Asia/Kolkata"
os.environ["LIBRE_POLL_INTERVAL_S"] = "1"

# Make the mytr-desk repo importable so we exercise syncd's *real* code.
MYTR_DESK = Path(r"C:\projects\mytr-desk")
if MYTR_DESK.exists():
    sys.path.insert(0, str(MYTR_DESK))

import uvicorn  # noqa: E402

from app.core.device_auth import generate_device_token  # noqa: E402
from app.device_database import DeviceSessionLocal  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.services.device_store import store  # noqa: E402
from proof.fake_librelinkup import TOTAL_READINGS, expected_epoch  # noqa: E402

# syncd's real modules (the code that ships on the device).
from device.syncd.client import fetch_backfill, iter_stream_readings, open_stream  # noqa: E402
from device.syncd.config import BackendConfig  # noqa: E402
from device.syncd.db import connect, get_last_ts, insert_readings  # noqa: E402

BACKEND_PORT = 9702
LLU_PORT = 9701
DROP_AFTER = 6  # force a disconnect after this many stream readings, once


def _uvicorn_server(app_path: str, port: int) -> uvicorn.Server:
    config = uvicorn.Config(app_path, host="127.0.0.1", port=port, log_level="warning")
    server = uvicorn.Server(config)
    server.install_signal_handlers = False
    return server


async def _wait_started(server: uvicorn.Server, timeout: float = 20.0) -> None:
    deadline = asyncio.get_event_loop().time() + timeout
    while not server.started:
        if asyncio.get_event_loop().time() > deadline:
            raise TimeoutError("server did not start in time")
        await asyncio.sleep(0.05)


async def _mint_device_token() -> str:
    raw, token_hash = generate_device_token()
    async with DeviceSessionLocal() as session:
        session.add(Device(user_id=uuid.uuid4(), token_hash=token_hash, name="proof-device"))
        await session.commit()
    return raw


def _backend_config() -> BackendConfig:
    return BackendConfig(
        ws_url=f"ws://127.0.0.1:{BACKEND_PORT}",
        ws_stream_path="/v1/devices/stream",
        base_url=f"http://127.0.0.1:{BACKEND_PORT}",
        readings_backfill_path="/v1/readings",
        reconnect_backoff_initial_s=0.2,
        reconnect_backoff_max_s=1,
        reconnect_backoff_multiplier=2,
    )


async def _syncd_loop(cfg: BackendConfig, token: str, conn: sqlite3.Connection,
                      state: dict) -> None:
    """Faithful copy of device/syncd/main.py::run() — stream-first, then
    backfill on every (re)connect — minus the Unix-socket event publisher
    (unavailable on Windows and irrelevant to the delivery guarantee).
    """
    while True:
        last_ts = get_last_ts(conn)
        try:
            async with open_stream(cfg, token) as ws:
                backfilled = await fetch_backfill(cfg, token, last_ts)
                inserted = insert_readings(conn, backfilled)
                if inserted:
                    state["backfilled_total"] += inserted
                count_this_conn = 0
                async for reading in iter_stream_readings(ws):
                    insert_readings(conn, [reading])
                    count_this_conn += 1
                    if not state["dropped_once"] and count_this_conn >= DROP_AFTER:
                        state["dropped_once"] = True
                        break  # forced mid-stream disconnect
        except Exception as exc:  # noqa: BLE001 - proof harness, keep looping
            state["last_error"] = repr(exc)
        await asyncio.sleep(0.2)


async def main() -> int:
    llu = _uvicorn_server("proof.fake_librelinkup:app", LLU_PORT)
    backend = _uvicorn_server("app.device_app:app", BACKEND_PORT)
    llu_task = asyncio.create_task(llu.serve())
    backend_task = asyncio.create_task(backend.serve())

    try:
        await _wait_started(llu)
        await _wait_started(backend)
        print(f"fake LibreLinkUp on :{LLU_PORT}, backend on :{BACKEND_PORT}")

        token = await _mint_device_token()
        print("minted device token; starting syncd stream-then-backfill loop\n")

        cfg = _backend_config()
        device_db = _TMP / "device.db"
        conn = connect(device_db)

        state = {"dropped_once": False, "backfilled_total": 0, "last_error": None}
        syncd_task = asyncio.create_task(_syncd_loop(cfg, token, conn, state))

        # Wait until the device has captured the full dataset (or time out).
        deadline = asyncio.get_event_loop().time() + 60
        while True:
            device_count = conn.execute("SELECT COUNT(*) FROM readings").fetchone()[0]
            backend_readings = await store.get_readings_since(0)
            if device_count >= TOTAL_READINGS and len(backend_readings) >= TOTAL_READINGS:
                break
            if asyncio.get_event_loop().time() > deadline:
                print("TIMEOUT waiting for full dataset")
                break
            await asyncio.sleep(0.3)

        syncd_task.cancel()
        try:
            await syncd_task
        except asyncio.CancelledError:
            pass

        return _verify(conn, await store.get_readings_since(0), state)
    finally:
        # Ask both servers to stop; give them a moment, then force-cancel so
        # teardown never hangs the proof.
        llu.should_exit = True
        backend.should_exit = True
        gather = asyncio.gather(llu_task, backend_task, return_exceptions=True)
        try:
            await asyncio.wait_for(gather, timeout=5)
        except asyncio.TimeoutError:
            for t in (llu_task, backend_task):
                t.cancel()
            await asyncio.gather(llu_task, backend_task, return_exceptions=True)


def _verify(conn: sqlite3.Connection, backend_readings: list[dict], state: dict) -> int:
    device_rows = conn.execute(
        "SELECT ts, mgdl, trend, sensor_id FROM readings ORDER BY ts ASC"
    ).fetchall()
    device_ts = [r[0] for r in device_rows]
    backend_ts = [r["ts"] for r in backend_readings]
    expected_ts = [expected_epoch(i) for i in range(TOTAL_READINGS)]

    ok = True

    def check(label: str, cond: bool, detail: str = "") -> None:
        nonlocal ok
        ok = ok and cond
        print(f"  [{'PASS' if cond else 'FAIL'}] {label}{(' - ' + detail) if detail else ''}")

    print("Results")
    print("-------")
    check("a forced mid-stream disconnect actually happened", state["dropped_once"])
    check("readings were recovered via REST backfill", state["backfilled_total"] > 0,
          f"{state['backfilled_total']} backfilled")
    check("device captured the full set (no gaps)", len(device_ts) == TOTAL_READINGS,
          f"{len(device_ts)}/{TOTAL_READINGS}")
    check("no duplicates on device", len(device_ts) == len(set(device_ts)))
    check("device set == backend set", set(device_ts) == set(backend_ts))
    check("timestamps parsed to correct UTC epochs", device_ts == expected_ts)

    labels = {r[0]: r[2] for r in device_rows}
    trends_present = set(labels.values())
    check("trend labels are device vocabulary", trends_present.issubset(
        {"flat", "rising", "rising_rapid", "falling", "falling_rapid"}),
        ", ".join(sorted(trends_present)))

    if device_ts:
        from datetime import datetime, timezone
        first = datetime.fromtimestamp(device_ts[0], timezone.utc).isoformat()
        last = datetime.fromtimestamp(device_ts[-1], timezone.utc).isoformat()
        print(f"\n  stored {len(device_ts)} readings, ts {device_ts[0]}..{device_ts[-1]}")
        print(f"  first (UTC): {first}   last (UTC): {last}")
        print("  (source strings were Asia/Kolkata local, i.e. UTC+5:30)")

    print("\n" + ("PROOF PASSED" if ok else "PROOF FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
