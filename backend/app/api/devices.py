"""REST endpoints the mytr-desk device consumes.

- POST /v1/devices/pair        open a QR pairing session, or poll it for a token
- POST /v1/devices/pair/claim  mobile app (authed user) claims a session by code
- GET  /v1/readings?since=<ts> backfill readings with ts > since
- POST /v1/voice/query         Phase-4 stub: authed, wired, returns 501

The WSS stream lives in app/api/websockets/device_stream.py.
"""

from __future__ import annotations

import secrets
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select

from ..core.config import settings
from ..core.device_auth import generate_device_token, get_current_device
from ..device_database import DeviceSessionLocal
from ..models.device import Device, PairingSession
from ..models.user import User
from ..services.device_store import store
from .auth import get_current_user

router = APIRouter()


# ── Schemas ───────────────────────────────────────────────────────────────────
class PairRequest(BaseModel):
    # Absent -> open a new session. Present -> poll that session for a token.
    pairing_id: Optional[str] = None
    # Optional friendly name the device suggests for itself.
    device_name: Optional[str] = None


class ClaimRequest(BaseModel):
    pairing_code: str
    device_name: Optional[str] = None
    sensor_id: Optional[str] = None


# ── Pairing ───────────────────────────────────────────────────────────────────
def _new_pairing_code() -> str:
    # 6 hex chars, easy to render in a QR and read back if needed.
    return secrets.token_hex(3).upper()


@router.post("/devices/pair")
async def pair(request: PairRequest):
    """Device-facing pairing handshake (no auth — the device isn't tokenised yet).

    First call (no pairing_id) opens a session and returns a code to render as a
    QR. Subsequent calls (with pairing_id) poll until the mobile app has claimed
    it, at which point the device token is returned exactly once.
    """
    now = datetime.utcnow()

    if request.pairing_id is None:
        session_row = PairingSession(
            pairing_code=_new_pairing_code(),
            status="pending",
            expires_at=now + timedelta(minutes=settings.PAIRING_SESSION_TTL_MIN),
        )
        async with DeviceSessionLocal() as session:
            session.add(session_row)
            await session.commit()
            await session.refresh(session_row)
        return {
            "pairing_id": str(session_row.id),
            "pairing_code": session_row.pairing_code,
            "status": "pending",
            "expires_at": session_row.expires_at.isoformat(),
        }

    # Poll path.
    async with DeviceSessionLocal() as session:
        result = await session.execute(
            select(PairingSession).where(PairingSession.id == request.pairing_id)
        )
        ps = result.scalar_one_or_none()
        if ps is None:
            raise HTTPException(status_code=404, detail="Unknown pairing session")

        if ps.status in ("pending", "claimed") and ps.expires_at < now:
            return {"status": "expired"}

        if ps.status == "pending":
            return {"status": "pending"}

        if ps.status == "claimed":
            # Deliver the token once, then burn it: clear the raw token and mark
            # the session consumed so a second poll can't re-read the secret.
            token = ps.device_token
            ps.device_token = None
            ps.status = "consumed"
            await session.commit()
            return {"status": "claimed", "device_token": token}

    # Already consumed (token was delivered) — nothing more to hand out.
    return {"status": "consumed"}


@router.post("/devices/pair/claim")
async def claim(request: ClaimRequest, current_user: User = Depends(get_current_user)):
    """Mobile-app-facing: an authenticated user claims a pending pairing code,
    which mints the device token the device will collect on its next poll."""
    now = datetime.utcnow()
    code = request.pairing_code.strip().upper()

    async with DeviceSessionLocal() as session:
        result = await session.execute(
            select(PairingSession).where(PairingSession.pairing_code == code)
        )
        ps = result.scalar_one_or_none()
        if ps is None:
            raise HTTPException(status_code=404, detail="Invalid pairing code")
        if ps.expires_at < now:
            raise HTTPException(status_code=410, detail="Pairing code has expired")
        if ps.status != "pending":
            raise HTTPException(status_code=409, detail="Pairing code already used")

        raw_token, token_hash = generate_device_token()
        device = Device(
            user_id=current_user.id,
            token_hash=token_hash,
            name=request.device_name,
            sensor_id=request.sensor_id,
        )
        session.add(device)
        await session.flush()  # assign device.id

        ps.status = "claimed"
        ps.device_id = device.id
        ps.device_token = raw_token
        ps.claimed_at = now
        await session.commit()

    return {"status": "claimed", "device_name": request.device_name}


# ── Backfill ──────────────────────────────────────────────────────────────────
@router.get("/readings")
async def readings(since: int = 0, device: Device = Depends(get_current_device)):
    """Return all stored readings with ts > since, ascending. syncd calls this
    right after connecting the stream to cover the pre-connection gap."""
    return {"readings": await store.get_readings_since(since)}


# ── Voice (Phase 4 stub) ──────────────────────────────────────────────────────
@router.post("/voice/query")
async def voice_query(device: Device = Depends(get_current_device)):
    """Authed and routed, but not yet implemented. Phase 4 fills the body
    (audio in -> STT -> Claude with glucose context -> TTS -> audio out)."""
    raise HTTPException(status_code=501, detail="voice query not implemented (Phase 4)")
