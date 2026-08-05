"""Shared websocket auth for /ws/app/stream and /ws/device/stream
(architecture-v3.md §2.6): the token travels in the Sec-WebSocket-Protocol
header — "bearer, <token>" — not the query string, per docs/TODO-security.md.

Mirrors `get_current_user` (app/api/auth.py) and `get_current_device`
(app/core/device_auth.py) for the websocket transport, where an HTTPException
isn't the right rejection mechanism — the caller closes the socket instead.
"""

from __future__ import annotations

from typing import Optional

from fastapi import WebSocket
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.security import (
    TOKEN_TYPE_ACCESS,
    TOKEN_TYPE_DEVICE_ACCESS,
    decode_token_payload,
)
from ...models.device import Device
from ...models.user import User


def extract_bearer_subprotocol_token(websocket: WebSocket) -> Optional[str]:
    """Parses "bearer, <token>" out of the Sec-WebSocket-Protocol header.
    Returns None on any malformed/missing header rather than raising —
    callers treat that identically to "no credentials"."""
    header = websocket.headers.get("sec-websocket-protocol")
    if not header:
        return None
    parts = [part.strip() for part in header.split(",")]
    if len(parts) != 2 or parts[0].lower() != "bearer" or not parts[1]:
        return None
    return parts[1]


async def authenticate_app_stream(websocket: WebSocket, db: AsyncSession) -> Optional[User]:
    token = extract_bearer_subprotocol_token(websocket)
    if token is None:
        return None
    payload = decode_token_payload(token, expected_type=TOKEN_TYPE_ACCESS)
    if payload is None:
        return None

    result = await db.execute(select(User).where(User.id == payload.get("sub")))
    user = result.scalar_one_or_none()
    if not user or payload.get("tv", 0) != (user.token_version or 0):
        return None
    return user


async def authenticate_device_stream(
    websocket: WebSocket, db: AsyncSession
) -> Optional[tuple[Device, str]]:
    token = extract_bearer_subprotocol_token(websocket)
    if token is None:
        return None
    payload = decode_token_payload(token, expected_type=TOKEN_TYPE_DEVICE_ACCESS)
    if payload is None:
        return None

    result = await db.execute(select(Device).where(Device.id == payload.get("sub")))
    device = result.scalar_one_or_none()
    if not device or device.revoked_at is not None:
        return None
    if payload.get("tv", 0) != (device.token_version or 0):
        return None
    return device, str(device.user_id)
