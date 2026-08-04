from fastapi import Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.device import Device
from .security import decode_token_payload, TOKEN_TYPE_DEVICE_ACCESS


async def get_current_device(
    authorization: str = Header(None),
    db: AsyncSession = Depends(get_db),
) -> tuple[Device, str]:
    """Mirrors `get_current_user` (app/api/auth.py) for the device audience.

    Resolves the device by the token's `sub`, rejects unpaired/revoked
    devices, and checks `tv` against `devices.token_version` so unpairing
    (or the owning user's logout-all) immediately invalidates it. Returns
    `(device, user_id)` — `user_id` comes from the device row itself, not
    the token's `uid` claim, so it always reflects current pairing state.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Not authenticated")
    token = authorization.replace("Bearer ", "")
    payload = decode_token_payload(token, expected_type=TOKEN_TYPE_DEVICE_ACCESS)
    if payload is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    result = await db.execute(select(Device).where(Device.id == payload.get("sub")))
    device = result.scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    if device.revoked_at is not None:
        raise HTTPException(status_code=401, detail="Device has been unpaired")
    if payload.get("tv", 0) != (device.token_version or 0):
        raise HTTPException(status_code=401, detail="Device session expired")

    return device, str(device.user_id)
