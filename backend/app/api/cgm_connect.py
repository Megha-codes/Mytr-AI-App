from datetime import datetime, timedelta
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.user import CGMDevice, User
from ..core.encryption import encrypt
from ..core.secrets_manager import secrets_manager
from .auth import get_current_user

router = APIRouter()

# ── Rate Limiting ────────────────────────────────────────────────────────────

# In-memory rate limiter for demo purposes.
# In production, use Redis.
_connection_attempts = {}

def check_rate_limit(user_id: UUID):
    now = datetime.utcnow()
    key = str(user_id)
    if key not in _connection_attempts:
        _connection_attempts[key] = []
    
    # Filter attempts in the last hour
    _connection_attempts[key] = [t for t in _connection_attempts[key] if now - t < timedelta(hours=1)]
    
    if len(_connection_attempts[key]) >= 5:
        raise HTTPException(
            status_code=429,
            detail="Too many attempts. Please wait before trying again.",
            headers={"Retry-After": "3600"}
        )
    
    _connection_attempts[key].append(now)

# ── Schemas ──────────────────────────────────────────────────────────────────

class ConnectionResult(BaseModel):
    connected:             bool
    device_id:             Optional[UUID] = None
    device_type:           str
    is_continuous:         bool = True
    supports_trend:        bool = True
    sensor_status:         Optional[str] = None  # "ACTIVE" | "NO_SENSOR" | "EXPIRED" | "WARMING_UP"
    last_reading_value:    Optional[int] = None
    last_reading_time:     Optional[datetime] = None
    trend:                 Optional[str] = None
    trend_arrow:           Optional[str] = None
    sensor_expiry_date:    Optional[datetime] = None
    sensor_days_remaining: Optional[int] = None
    error_code:            Optional[str] = None
    error_message:         Optional[str] = None

class LibreConnectRequest(BaseModel):
    email:    str
    password: str

class DeviceMetadata(BaseModel):
    id:                 UUID
    device_type:        str
    is_active:          bool
    connected_at:       datetime
    sensor_status:      Optional[str]
    sensor_expiry_date: Optional[datetime]

# ── FreeStyle Libre ──────────────────────────────────────────────────────────

@router.post("/cgm/connect/libre", response_model=ConnectionResult)
async def connect_libre(
    request: LibreConnectRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user.id
    check_rate_limit(user_id)

    from ..services.cgm.libre_service import LibreCGMService
    libre_service = LibreCGMService()
    validation = await libre_service.validate_credentials(request.email, request.password)

    if not validation.success:
        return ConnectionResult(
            connected=False,
            device_type="LIBRE",
            error_code="INVALID_CREDENTIALS",
            error_message=validation.error_message
        )

    # Encrypt before storage
    await secrets_manager.store_libre_credentials(
        user_id=str(user_id),
        email=request.email,
        encrypted_password=encrypt(request.password),
    )

    device_type = f"LIBRE_{validation.sensor_generation}"
    expiry_date = datetime.fromisoformat(validation.sensor_expiry_date) if validation.sensor_expiry_date else None

    device = await _register_cgm_device(
        db=db,
        user_id=user_id,
        device_type=device_type,
        is_continuous=True,
        supports_trend=True,
        sensor_status="ACTIVE",
        sensor_expiry_date=expiry_date
    )

    return ConnectionResult(
        connected=True,
        device_id=device.id,
        device_type=device_type,
        sensor_status="ACTIVE",
        sensor_expiry_date=expiry_date
    )

# ── Manual Entry ─────────────────────────────────────────────────────────────

@router.post("/cgm/connect/manual", response_model=ConnectionResult)
async def connect_manual(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    device = await _register_cgm_device(
        db=db,
        user_id=current_user.id,
        device_type="MANUAL",
        is_continuous=False,
        supports_trend=False,
    )
    return ConnectionResult(
        connected=True,
        device_id=device.id,
        device_type="MANUAL",
        is_continuous=False,
        supports_trend=False
    )

# ── Device Management ────────────────────────────────────────────────────────

@router.get("/cgm/devices", response_model=List[DeviceMetadata])
async def list_devices(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CGMDevice).where(
            CGMDevice.user_id == current_user.id,
            CGMDevice.deleted_at == None
        )
    )
    devices = result.scalars().all()
    return [
        DeviceMetadata(
            id=d.id,
            device_type=d.device_type,
            is_active=d.is_active,
            connected_at=d.connected_at,
            sensor_status=d.sensor_status,
            sensor_expiry_date=d.sensor_expiry_date
        ) for d in devices
    ]

@router.delete("/cgm/devices/{device_id}")
async def disconnect_device(
    device_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CGMDevice).where(
            CGMDevice.id == device_id,
            CGMDevice.user_id == current_user.id
        )
    )
    device = result.scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    # Wipe Secrets Manager
    base_type = device.device_type.split('_')[0].lower()
    await secrets_manager.delete_credentials(str(current_user.id), base_type)

    # Soft-delete row
    device.deleted_at = datetime.utcnow()
    device.is_active = False
    await db.commit()

    return {"success": True}

@router.post("/cgm/reconnect/{device_type}", response_model=ConnectionResult)
async def reconnect_device(
    device_type: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # This would involve re-validating stored credentials
    # For now, we'll just return a success if we have credentials
    if "LIBRE" in device_type:
        creds = await secrets_manager.get_libre_credentials(str(current_user.id))
        if creds:
            return ConnectionResult(connected=True, device_type=device_type)

    return ConnectionResult(connected=False, device_type=device_type, error_message="No credentials stored")

# ── Shared helper ─────────────────────────────────────────────────────────────

async def _register_cgm_device(
    db: AsyncSession,
    user_id: UUID,
    device_type: str,
    is_continuous: bool,
    supports_trend: bool,
    sensor_status: str = "ACTIVE",
    sensor_expiry_date: datetime = None
) -> CGMDevice:
    # Deactivate other devices
    await db.execute(
        update(CGMDevice)
        .where(CGMDevice.user_id == user_id, CGMDevice.is_active == True)
        .values(is_active=False)
    )

    new_device = CGMDevice(
        user_id=user_id,
        device_type=device_type,
        is_active=True,
        is_continuous=is_continuous,
        supports_trend=supports_trend,
        sensor_status=sensor_status,
        sensor_expiry_date=sensor_expiry_date
    )
    db.add(new_device)
    await db.commit()
    await db.refresh(new_device)
    return new_device
