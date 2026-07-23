"""WSS /v1/devices/stream — live glucose readings to paired desk devices.

Each message is one JSON reading in the exact shape syncd expects:
``{"ts", "mgdl", "trend", "sensor_id"}``. Auth is the device bearer token in
the ``Authorization`` header, same as the REST endpoints.

Delivery guarantee (what syncd's stream-first-then-backfill ordering relies on):
we ``subscribe()`` to the hub *before* accepting the socket, so from the moment
the connection is accepted onward, every reading the poller publishes is
delivered here in order — nothing can slip through the gap between the device
connecting and issuing its ``?since=`` backfill.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from ...core.device_auth import authenticate_ws_token
from ...services.device_hub import hub

logger = logging.getLogger("mytr.device_stream")

router = APIRouter()


@router.websocket("/v1/devices/stream")
async def device_stream(websocket: WebSocket) -> None:
    device = await authenticate_ws_token(websocket.headers.get("authorization"))
    if device is None:
        # Reject the handshake before accepting — syncd treats this as a normal
        # disconnect and reconnects with backoff.
        await websocket.close(code=1008)
        return

    # Subscribe before accept so no reading published during the handshake is
    # lost: the queue starts buffering immediately, we drain it after accepting.
    queue = hub.subscribe()
    try:
        await websocket.accept()
        logger.info("device stream connected (device_id=%s)", device.id)
        while True:
            reading = await queue.get()
            await websocket.send_json(reading)
    except WebSocketDisconnect:
        logger.info("device stream disconnected (device_id=%s)", device.id)
    except Exception:
        logger.info("device stream closed (device_id=%s)", device.id)
    finally:
        hub.unsubscribe(queue)
