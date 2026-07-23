"""Bearer device-token auth for the mytr-desk endpoints.

Device tokens are opaque random strings minted at pairing time and handed to
the device once. Only their SHA-256 hash is stored, so the raw token can't leak
from the database or logs. Every stream / backfill / voice request presents it
as ``Authorization: Bearer <token>``; we hash the presented token and look up a
non-revoked device by that hash.
"""

from __future__ import annotations

import hashlib
import secrets

from fastapi import Header, HTTPException
from sqlalchemy import select

from ..device_database import DeviceSessionLocal
from ..models.device import Device


def generate_device_token() -> tuple[str, str]:
    """Return (raw_token, token_hash). The raw token is shown to the device
    exactly once; only the hash is persisted."""
    raw = secrets.token_urlsafe(32)
    return raw, hash_device_token(raw)


def hash_device_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _extract_bearer(authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing device token")
    return authorization[len("Bearer ") :].strip()


async def _device_for_token(raw_token: str) -> Device | None:
    token_hash = hash_device_token(raw_token)
    async with DeviceSessionLocal() as session:
        result = await session.execute(
            select(Device).where(
                Device.token_hash == token_hash,
                Device.revoked_at.is_(None),
            )
        )
        return result.scalar_one_or_none()


async def get_current_device(authorization: str | None = Header(None)) -> Device:
    """FastAPI dependency: resolve the device from its bearer token or 401."""
    token = _extract_bearer(authorization)
    device = await _device_for_token(token)
    if device is None:
        raise HTTPException(status_code=401, detail="Invalid or revoked device token")
    return device


async def authenticate_ws_token(authorization: str | None) -> Device | None:
    """WebSocket-side check (no HTTPException): returns the device or None."""
    if not authorization or not authorization.startswith("Bearer "):
        return None
    return await _device_for_token(authorization[len("Bearer ") :].strip())
