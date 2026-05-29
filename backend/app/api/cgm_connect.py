import httpx
import uuid
from datetime import datetime, timedelta
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.user import CGMDevice
from ..core.config import settings
from ..core.encryption import encrypt
from ..core.secrets_manager import secrets_manager

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

class DexcomConnectRequest(BaseModel):
    code:  str
    state: str

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

# ── Dexcom OAuth2 ────────────────────────────────────────────────────────────

# Temporary store for OAuth states (CSRF protection)
_oauth_states = {}

@router.get("/cgm/oauth/dexcom/url")
async def get_dexcom_url(user_id: UUID):
    state = str(uuid.uuid4())
    _oauth_states[state] = user_id
    
    url = (
        f"https://sandbox-api.dexcom.com/v2/oauth2/login" # Use sandbox for dev
        f"?client_id={settings.DEXCOM_CLIENT_ID}"
        f"&redirect_uri={settings.DEXCOM_REDIRECT_URI}"
        f"&response_type=code"
        f"&scope=offline_access"
        f"&state={state}"
    )
    return {"url": url}

@router.post("/cgm/connect/dexcom", response_model=ConnectionResult)
async def connect_dexcom(
    request: DexcomConnectRequest,
    user_id: UUID, # Assume authenticated user_id is provided via middleware/dependency
    db: AsyncSession = Depends(get_db),
):
    check_rate_limit(user_id)
    
    # Validate CSRF state
    if request.state not in _oauth_states or _oauth_states[request.state] != user_id:
        raise HTTPException(status_code=403, detail="Invalid OAuth state (CSRF)")
    del _oauth_states[request.state]

    async with httpx.AsyncClient(timeout=15.0) as client:
        token_response = await client.post(
            settings.DEXCOM_TOKEN_URL,
            data={
                "grant_type":    "authorization_code",
                "code":          request.code,
                "redirect_uri":  settings.DEXCOM_REDIRECT_URI,
                "client_id":     settings.DEXCOM_CLIENT_ID,
                "client_secret": settings.DEXCOM_CLIENT_SECRET,
            },
        )

    if token_response.status_code != 200:
        return ConnectionResult(
            connected=False,
            device_type="DEXCOM",
            error_code="TOKEN_EXCHANGE_FAILED",
            error_message=f"Dexcom token exchange failed: {token_response.text}"
        )

    tokens = token_response.json()
    expires_at = datetime.utcnow() + timedelta(seconds=tokens["expires_in"])

    await secrets_manager.store_dexcom_tokens(
        user_id=str(user_id),
        access_token=tokens["access_token"],
        refresh_token=tokens["refresh_token"],
        expires_at=expires_at,
    )

    device = await _register_cgm_device(
        db=db,
        user_id=user_id,
        device_type="DEXCOM_G7",
        is_continuous=True,
        supports_trend=True,
        sensor_status="ACTIVE",
        sensor_expiry_date=expires_at # Simplified for demo
    )

    return ConnectionResult(
        connected=True,
        device_id=device.id,
        device_type=device.device_type,
        sensor_status="ACTIVE",
        sensor_expiry_date=device.sensor_expiry_date
    )


# ── FreeStyle Libre ──────────────────────────────────────────────────────────

@router.post("/cgm/connect/libre", response_model=ConnectionResult)
async def connect_libre(
    request: LibreConnectRequest,
    user_id: UUID,
    db: AsyncSession = Depends(get_db),
):
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
    user_id: UUID,
    db: AsyncSession = Depends(get_db),
):
    device = await _register_cgm_device(
        db=db,
        user_id=user_id,
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
    user_id: UUID,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CGMDevice).where(
            CGMDevice.user_id == user_id,
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
    user_id: UUID,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CGMDevice).where(
            CGMDevice.id == device_id,
            CGMDevice.user_id == user_id
        )
    )
    device = result.scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    # Wipe Secrets Manager
    base_type = device.device_type.split('_')[0].lower()
    await secrets_manager.delete_credentials(str(user_id), base_type)

    # Soft-delete row
    device.deleted_at = datetime.utcnow()
    device.is_active = False
    await db.commit()

    return {"success": True}

@router.post("/cgm/reconnect/{device_type}", response_model=ConnectionResult)
async def reconnect_device(
    device_type: str,
    user_id: UUID,
    db: AsyncSession = Depends(get_db),
):
    # This would involve re-validating stored credentials
    # For now, we'll just return a success if we have credentials
    if "DEXCOM" in device_type:
        creds = await secrets_manager.get_dexcom_credentials(str(user_id))
        if creds:
            return ConnectionResult(connected=True, device_type=device_type)
    elif "LIBRE" in device_type:
        creds = await secrets_manager.get_libre_credentials(str(user_id))
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
