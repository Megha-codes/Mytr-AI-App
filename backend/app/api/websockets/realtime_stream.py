"""/ws/app/stream and /ws/device/stream (architecture-v3.md §2.6): the one
realtime mechanism for both audiences, on top of the fanout hub built in
Phase A. Auth differs (user JWT vs device JWT, via the Sec-WebSocket-Protocol
header); everything downstream — hello, ping, resume — is identical, so both
routes share `_run_stream`.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging

from fastapi import APIRouter, Depends, WebSocket
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.websockets import WebSocketDisconnect

from ...database import get_db
from ...services.realtime.envelope import (
    CLIENT_FRAME_TYPE_RESUME,
    HEARTBEAT_SECONDS,
    RESYNC_FRAME,
)
from ...services.realtime.fanout_hub import fanout_hub
from ...services.realtime.ws_auth import authenticate_app_stream, authenticate_device_stream
from ...timescale_database import TimescaleSessionLocal

router = APIRouter()
logger = logging.getLogger("mytr.realtime_stream")

# Auth rejection before the handshake completes — same code the retired
# /ws/glucose used for "not authenticated" (Policy Violation).
CLOSE_UNAUTHENTICATED = 1008


async def _writer_loop(websocket: WebSocket, user_id, queue: asyncio.Queue) -> None:
    while True:
        try:
            envelope = await asyncio.wait_for(queue.get(), timeout=HEARTBEAT_SECONDS)
        except asyncio.TimeoutError:
            envelope = fanout_hub.build_ping(user_id)
        await websocket.send_json(envelope)


async def _reader_loop(websocket: WebSocket, user_id) -> None:
    """Handles client-initiated control frames — currently just the
    reconnect resume handshake (§2.6): `{"type":"resume","since_seq":N}`."""
    while True:
        raw = await websocket.receive_text()
        try:
            frame = json.loads(raw)
        except ValueError:
            continue
        if frame.get("type") != CLIENT_FRAME_TYPE_RESUME:
            continue
        since_seq = frame.get("since_seq", 0)
        result = await fanout_hub.resume(user_id, since_seq, TimescaleSessionLocal)
        if result.resync:
            await websocket.send_json(RESYNC_FRAME)
        else:
            for envelope in result.envelopes:
                await websocket.send_json(envelope)


async def _run_stream(websocket: WebSocket, user_id) -> None:
    queue = fanout_hub.subscribe(user_id)
    try:
        await websocket.send_json(fanout_hub.build_hello(user_id))
        writer = asyncio.create_task(_writer_loop(websocket, user_id, queue))
        reader = asyncio.create_task(_reader_loop(websocket, user_id))
        done, pending = await asyncio.wait({writer, reader}, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task
        for task in done:
            exc = task.exception()
            if exc is not None and not isinstance(exc, WebSocketDisconnect):
                raise exc
    except WebSocketDisconnect:
        pass
    finally:
        fanout_hub.unsubscribe(user_id, queue)


@router.websocket("/ws/app/stream")
async def app_stream(websocket: WebSocket, db: AsyncSession = Depends(get_db)) -> None:
    user = await authenticate_app_stream(websocket, db)
    if user is None:
        await websocket.close(code=CLOSE_UNAUTHENTICATED)
        return

    await websocket.accept(subprotocol="bearer")
    await _run_stream(websocket, user.id)


@router.websocket("/ws/device/stream")
async def device_stream(websocket: WebSocket, db: AsyncSession = Depends(get_db)) -> None:
    resolved = await authenticate_device_stream(websocket, db)
    if resolved is None:
        await websocket.close(code=CLOSE_UNAUTHENTICATED)
        return

    _device, user_id = resolved
    await websocket.accept(subprotocol="bearer")
    await _run_stream(websocket, user_id)
