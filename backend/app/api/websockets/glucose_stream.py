from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Dict
import asyncio
import json
from datetime import datetime

from app.database import get_db
from app.services.cgm.factory import cgm_service_factory
from app.models.user import CGMDevice, InsulinProfile, User
from app.core.security import decode_token_payload, TOKEN_TYPE_ACCESS
from sqlalchemy import select, text

router = APIRouter()

class GlucoseConnectionManager:
    def __init__(self):
        # user_id → active WebSocket connection
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, user_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[user_id] = websocket

    def disconnect(self, user_id: str):
        self.active_connections.pop(user_id, None)

    async def send_reading(self, user_id: str, reading: dict):
        websocket = self.active_connections.get(user_id)
        if websocket:
            try:
                await websocket.send_json(reading)
            except Exception:
                self.disconnect(user_id)


manager = GlucoseConnectionManager()

async def get_active_cgm_device(user_id: str, db: AsyncSession):
    device = await db.execute(select(CGMDevice).where(CGMDevice.user_id == user_id).where(CGMDevice.is_active == True))
    return device.scalar_one_or_none()

async def get_last_manual_reading(user_id: str, db: AsyncSession):
    from app.timescale_database import TimescaleSessionLocal
    from app.models.glucose_reading import GlucoseReadingModel
    from sqlalchemy import desc
    from uuid import UUID as PUUID

    try:
        async with TimescaleSessionLocal() as ts:
            result = await ts.execute(
                select(GlucoseReadingModel)
                .where(GlucoseReadingModel.user_id == PUUID(user_id))
                .where(GlucoseReadingModel.device_type == "MANUAL")
                .order_by(desc(GlucoseReadingModel.recorded_at))
                .limit(1)
            )
            row = result.scalars().first()
        if row:
            class _R:
                value     = row.value_mgdl
                timestamp = row.recorded_at
            return _R()
    except Exception:
        pass
    return None

async def get_insulin_profile(user_id: str, db: AsyncSession):
    # Dummy mock for insulin profile
    class MockProfile:
        target_glucose_min = 80
        target_glucose_max = 130
    return MockProfile()

async def store_glucose_reading(reading, user_id: str, db: AsyncSession):
    from ...models.glucose_reading import GlucoseReadingModel
    from ...timescale_database import TimescaleSessionLocal
    from datetime import timezone

    recorded_at = reading.timestamp
    if recorded_at.tzinfo is None:
        recorded_at = recorded_at.replace(tzinfo=timezone.utc)

    async with TimescaleSessionLocal() as ts_session:
        record = GlucoseReadingModel(
            user_id=user_id,
            value_mgdl=reading.value,
            trend=reading.trend,
            trend_arrow=reading.trend_arrow,
            device_type=reading.device_type,
            is_continuous=reading.is_continuous,
            recorded_at=recorded_at,
        )
        ts_session.add(record)
        await ts_session.commit()

def _check_alerts(value: int, user_id: str, db: AsyncSession) -> list[dict]:
    # synchronous mock version or we can await if necessary. The user snippet has it synchronous.
    # We will instantiate the mock profile synchronously here as per the user's snippet.
    class MockProfile:
        target_glucose_min = 80
        target_glucose_max = 130
    profile = MockProfile()
    
    alerts = []
    if value < 70:
        alerts.append({
            "type": "HYPO",
            "severity": "URGENT",
            "message": f"Glucose critically low: {value} mg/dL",
        })
    elif value < profile.target_glucose_min:
        alerts.append({
            "type": "LOW",
            "severity": "WARNING",
            "message": f"Glucose below target: {value} mg/dL",
        })
    elif value > 250:
        alerts.append({
            "type": "HYPER",
            "severity": "URGENT",
            "message": f"Glucose critically high: {value} mg/dL",
        })
    elif value > profile.target_glucose_max:
        alerts.append({
            "type": "HIGH",
            "severity": "WARNING",
            "message": f"Glucose above target: {value} mg/dL",
        })
    return alerts


async def _authenticate_ws(token: str, db: AsyncSession) -> User | None:
    payload = decode_token_payload(token, expected_type=TOKEN_TYPE_ACCESS)
    if payload is None:
        return None

    result = await db.execute(select(User).where(User.id == payload.get("sub")))
    user = result.scalar_one_or_none()
    if not user or payload.get("tv", 0) != (user.token_version or 0):
        return None
    return user


@router.websocket("/ws/glucose")
async def glucose_websocket(
    websocket: WebSocket,
    token: str = Query(...),
    db: AsyncSession = Depends(get_db)
):
    authenticated_user = await _authenticate_ws(token, db)
    if authenticated_user is None:
        await websocket.close(code=1008)
        return

    user_id = str(authenticated_user.id)
    await manager.connect(user_id, websocket)

    try:
        # Get user's CGM device type
        cgm_device = await get_active_cgm_device(user_id, db)

        # Treat the specific manual types as "MANUAL" for websocket logic
        device_type_str = cgm_device.device_type if cgm_device else "MANUAL"
        
        if not cgm_device or device_type_str == "MANUAL":
            # Manual entry user — send last stored reading then wait for pushes
            # from POST /glucose/manual (which calls manager.send_reading directly)
            last_reading = await get_last_manual_reading(user_id, db)
            if last_reading:
                await websocket.send_json({
                    "type": "MANUAL_READING",
                    "value": last_reading.value,
                    "timestamp": last_reading.timestamp.isoformat(),
                    "is_live": False,
                })

            # Keep connection alive — sends updates when
            # user manually logs a reading
            while True:
                await asyncio.sleep(30)
                await websocket.send_json({"type": "PING"})

        else:
            # CGM or Bluetooth BGM — start polling loop
            await _start_polling_loop(
                websocket=websocket,
                user_id=user_id,
                device_type=device_type_str,
                db=db,
            )

    except WebSocketDisconnect:
        manager.disconnect(user_id)


async def _start_polling_loop(
    websocket: WebSocket,
    user_id: str,
    device_type: str,
    db: AsyncSession,
):
    cgm_service = cgm_service_factory(device_type)

    # Libre sensors update roughly every minute
    poll_interval_seconds = {
        "LIBRE_2":   60,
        "LIBRE_3":   60,
    }.get(device_type, 60)

    last_sent_timestamp = None

    while True:
        try:
            reading = await cgm_service.get_latest_reading(user_id)

            if reading and reading.timestamp != last_sent_timestamp:
                # New reading available — send to Flutter
                payload = {
                    "type": "GLUCOSE_READING",
                    "value": reading.value,
                    "unit": "mg/dL",
                    "timestamp": reading.timestamp.isoformat(),
                    "trend": reading.trend,           # RISING / STABLE / FALLING
                    "trend_arrow": reading.trend_arrow, # ↑ ↗ → ↘ ↓
                    "is_live": True,
                    "device_type": device_type,

                    # Alert flags — Flutter renders banners for these
                    "alerts": _check_alerts(reading.value, user_id, db),
                }

                await websocket.send_json(payload)

                # Store in TimescaleDB
                await store_glucose_reading(reading, user_id, db)

                last_sent_timestamp = reading.timestamp

            await asyncio.sleep(poll_interval_seconds)

        except WebSocketDisconnect:
            break
        except Exception as e:
            # Send error state to Flutter — show "CGM unavailable" UI
            await websocket.send_json({
                "type": "CGM_ERROR",
                "message": "Unable to reach CGM. Retrying...",
            })
            await asyncio.sleep(30)
