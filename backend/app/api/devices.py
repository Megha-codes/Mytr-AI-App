import asyncio
import secrets
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.device import Device, DevicePairingCode
from ..models.user import User
from ..core.security import (
    create_device_access_token,
    create_device_refresh_token,
    decode_token_payload,
    DEVICE_ACCESS_TOKEN_EXPIRE_MINUTES,
    TOKEN_TYPE_DEVICE_REFRESH,
)
from ..schemas.device import (
    DeviceClaimRequest,
    DeviceClaimResponse,
    DeviceListItem,
    DevicePairPollRequest,
    DevicePairStartRequest,
    DevicePairStartResponse,
    DeviceRenameRequest,
    DeviceTokenRefreshRequest,
    DeviceTokens,
)
from .auth import get_current_user

router = APIRouter()

# ── Pairing codes ────────────────────────────────────────────────────────────
# Crockford base32 minus its remaining vowels (A, E) — Crockford already drops
# I, L, O, U — so no accidental words and no 0/O·1/I confusion when read aloud.
_CODE_ALPHABET = "0123456789BCDFGHJKMNPQRSTVWXYZ"
_CODE_LENGTH = 8
_PAIRING_CODE_TTL = timedelta(minutes=10)


def _generate_code() -> str:
    return "".join(secrets.choice(_CODE_ALPHABET) for _ in range(_CODE_LENGTH))


def _format_code(code: str) -> str:
    return f"{code[:4]}-{code[4:]}"


def _normalize_code(raw: str) -> str:
    return raw.replace("-", "").replace(" ", "").upper()


# ── Rate limiting ─────────────────────────────────────────────────────────────
# In-memory, per-process — same "demo now, Redis in production" posture as the
# existing limiters in cgm_connect.py and auth.py.
_pair_start_attempts: dict = defaultdict(list)
_pair_poll_failures: dict = defaultdict(list)

PAIR_START_LIMIT = 5
PAIR_START_WINDOW_SECONDS = 3600  # 1 hour, per hardware_id + IP

PAIR_POLL_FAILURE_LIMIT = 10
PAIR_POLL_FAILURE_WINDOW_SECONDS = 60  # 1 minute, per hardware_id


def _check_pair_start_rate_limit(hardware_id: str, ip: str) -> None:
    key = f"{hardware_id}:{ip}"
    now = time.time()
    _pair_start_attempts[key] = [
        t for t in _pair_start_attempts[key] if now - t < PAIR_START_WINDOW_SECONDS
    ]
    if len(_pair_start_attempts[key]) >= PAIR_START_LIMIT:
        raise HTTPException(status_code=429, detail="Too many pairing attempts. Try again later.")
    _pair_start_attempts[key].append(now)


def _check_pair_poll_failure_rate_limit(hardware_id: str) -> None:
    now = time.time()
    _pair_poll_failures[hardware_id] = [
        t for t in _pair_poll_failures[hardware_id] if now - t < PAIR_POLL_FAILURE_WINDOW_SECONDS
    ]
    if len(_pair_poll_failures[hardware_id]) >= PAIR_POLL_FAILURE_LIMIT:
        raise HTTPException(status_code=429, detail="Too many pairing attempts. Try again later.")
    _pair_poll_failures[hardware_id].append(now)


# ── Device-initiated pairing (no auth) ────────────────────────────────────────

@router.post("/device/pair/start", response_model=DevicePairStartResponse)
async def pair_start(
    request: DevicePairStartRequest,
    http_request: Request,
    db: AsyncSession = Depends(get_db),
):
    ip = http_request.client.host if http_request.client else "unknown"
    _check_pair_start_rate_limit(request.hardware_id, ip)

    result = await db.execute(select(Device).where(Device.hardware_id == request.hardware_id))
    device = result.scalar_one_or_none()
    if device is None:
        device = Device(hardware_id=request.hardware_id, firmware_version=request.firmware_version)
        db.add(device)
    else:
        device.firmware_version = request.firmware_version
    await db.commit()
    await db.refresh(device)

    # Only one live code per device — starting again supersedes any
    # still-open code from a previous attempt.
    await db.execute(
        delete(DevicePairingCode).where(DevicePairingCode.hardware_id == request.hardware_id)
    )

    code = _generate_code()
    expires_at = datetime.now(timezone.utc) + _PAIRING_CODE_TTL
    db.add(
        DevicePairingCode(
            code=code,
            hardware_id=request.hardware_id,
            device_id=device.id,
            expires_at=expires_at,
        )
    )
    await db.commit()

    return DevicePairStartResponse(
        code=_format_code(code),
        expires_in=int(_PAIRING_CODE_TTL.total_seconds()),
    )


# Long-poll tuning — module-level so tests can shrink them instead of a real
# 30-second wait.
_POLL_INTERVAL_SECONDS = 1.0
_POLL_TIMEOUT_SECONDS = 30.0


@router.post("/device/pair/poll")
async def pair_poll(
    request: DevicePairPollRequest,
    db: AsyncSession = Depends(get_db),
):
    code = _normalize_code(request.code)
    deadline = time.monotonic() + _POLL_TIMEOUT_SECONDS

    while True:
        db.expire_all()
        result = await db.execute(
            select(DevicePairingCode).where(
                DevicePairingCode.code == code,
                DevicePairingCode.hardware_id == request.hardware_id,
            )
        )
        pairing_code = result.scalar_one_or_none()

        if pairing_code is None:
            # Doesn't exist for this hardware_id at all — either a guess, or
            # a code some *other* hardware_id owns. Count it as an attack.
            _check_pair_poll_failure_rate_limit(request.hardware_id)
            raise HTTPException(status_code=404, detail="Unknown pairing code")

        if pairing_code.expires_at <= datetime.now(timezone.utc):
            raise HTTPException(status_code=404, detail="Pairing code expired")

        if pairing_code.claimed_by is not None:
            device_result = await db.execute(select(Device).where(Device.id == pairing_code.device_id))
            device = device_result.scalar_one_or_none()
            if device is None:
                raise HTTPException(status_code=404, detail="Device not found")

            tv = device.token_version or 0
            access_token = create_device_access_token(device.id, device.user_id, token_version=tv)
            refresh_token = create_device_refresh_token(device.id, device.user_id, token_version=tv)

            # Single-use: consumed on pickup, not on claim.
            await db.delete(pairing_code)
            await db.commit()

            return DeviceTokens(
                device_access_token=access_token,
                device_refresh_token=refresh_token,
                user_id=str(device.user_id),
                device_name=device.name,
                expires_in=DEVICE_ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            )

        if time.monotonic() >= deadline:
            return JSONResponse(status_code=202, content={"status": "pending"})

        await asyncio.sleep(_POLL_INTERVAL_SECONDS)


# ── App-side claim + device management (user JWT) ─────────────────────────────

@router.post("/devices/pair", response_model=DeviceClaimResponse)
async def claim_device(
    request: DeviceClaimRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    code = _normalize_code(request.code)
    result = await db.execute(select(DevicePairingCode).where(DevicePairingCode.code == code))
    pairing_code = result.scalar_one_or_none()

    if pairing_code is None or pairing_code.expires_at <= datetime.now(timezone.utc):
        raise HTTPException(status_code=404, detail="Unknown or expired pairing code")
    if pairing_code.claimed_by is not None:
        raise HTTPException(status_code=409, detail="Pairing code already claimed")

    device_result = await db.execute(select(Device).where(Device.id == pairing_code.device_id))
    device = device_result.scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=404, detail="Device not found")

    # A device already actively paired to someone else must be unpaired
    # first — a fresh pairing code alone doesn't transfer ownership.
    if device.user_id is not None and device.revoked_at is None and device.user_id != current_user.id:
        raise HTTPException(status_code=409, detail="Device is already paired to another account")

    device.user_id = current_user.id
    device.paired_at = datetime.now(timezone.utc)
    device.revoked_at = None  # re-pairing after an explicit unpair re-activates it
    if request.name is not None:
        device.name = request.name

    pairing_code.claimed_by = current_user.id
    await db.commit()
    await db.refresh(device)

    return DeviceClaimResponse(device_id=device.id, name=device.name, paired_at=device.paired_at)


@router.get("/devices", response_model=List[DeviceListItem])
async def list_devices(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Device).where(Device.user_id == current_user.id, Device.revoked_at.is_(None))
    )
    devices = result.scalars().all()
    return [
        DeviceListItem(
            device_id=d.id,
            name=d.name,
            kind=d.kind,
            last_seen_at=d.last_seen_at,
            firmware_version=d.firmware_version,
            paired_at=d.paired_at,
        )
        for d in devices
    ]


async def _get_owned_device(device_id: UUID, current_user: User, db: AsyncSession) -> Device:
    result = await db.execute(
        select(Device).where(
            Device.id == device_id,
            Device.user_id == current_user.id,
            Device.revoked_at.is_(None),
        )
    )
    device = result.scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=404, detail="Device not found")
    return device


@router.patch("/devices/{device_id}", response_model=DeviceListItem)
async def rename_device(
    device_id: UUID,
    request: DeviceRenameRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    device = await _get_owned_device(device_id, current_user, db)
    device.name = request.name
    await db.commit()
    await db.refresh(device)

    return DeviceListItem(
        device_id=device.id,
        name=device.name,
        kind=device.kind,
        last_seen_at=device.last_seen_at,
        firmware_version=device.firmware_version,
        paired_at=device.paired_at,
    )


@router.delete("/devices/{device_id}")
async def unpair_device(
    device_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    device = await _get_owned_device(device_id, current_user, db)
    device.revoked_at = datetime.now(timezone.utc)
    device.token_version = (device.token_version or 0) + 1
    await db.commit()

    return {"success": True}


# ── Device token refresh (device refresh token) ────────────────────────────────

@router.post("/device/token/refresh", response_model=DeviceTokens)
async def refresh_device_token(
    request: DeviceTokenRefreshRequest,
    db: AsyncSession = Depends(get_db),
):
    payload = decode_token_payload(request.refresh_token, expected_type=TOKEN_TYPE_DEVICE_REFRESH)
    if payload is None:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    result = await db.execute(select(Device).where(Device.id == payload.get("sub")))
    device = result.scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=401, detail="Device not found")
    if device.revoked_at is not None:
        raise HTTPException(status_code=401, detail="Device has been unpaired")
    if payload.get("tv", 0) != (device.token_version or 0):
        raise HTTPException(status_code=401, detail="Device session expired")

    tv = device.token_version or 0
    access_token = create_device_access_token(device.id, device.user_id, token_version=tv)
    new_refresh_token = create_device_refresh_token(device.id, device.user_id, token_version=tv)

    return DeviceTokens(
        device_access_token=access_token,
        device_refresh_token=new_refresh_token,
        user_id=str(device.user_id),
        device_name=device.name,
        expires_in=DEVICE_ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )
