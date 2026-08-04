from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.glucose_reading import GlucoseReadingModel
from ..models.user import User
from ..services.realtime.fanout_hub import fanout_hub
from ..timescale_database import TimescaleSessionLocal
from .auth import get_current_user
from .websockets.glucose_stream import manager, _check_alerts

router = APIRouter()


class ManualGlucoseRequest(BaseModel):
    value_mgdl: int
    timestamp: datetime


@router.post("/glucose/manual")
async def log_manual_glucose(
    request: ManualGlucoseRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not 40 <= request.value_mgdl <= 400:
        raise HTTPException(
            status_code=400,
            detail="Glucose value out of valid range (40–400 mg/dL)",
        )

    recorded_at = request.timestamp
    if recorded_at.tzinfo is None:
        recorded_at = recorded_at.replace(tzinfo=timezone.utc)

    reading_id = None
    async with TimescaleSessionLocal() as ts_session:
        reading = GlucoseReadingModel(
            user_id=current_user.id,
            value_mgdl=request.value_mgdl,
            trend=None,
            trend_arrow="→",
            device_type="MANUAL",
            is_continuous=False,
            recorded_at=recorded_at,
        )
        ts_session.add(reading)
        await ts_session.commit()
        await ts_session.refresh(reading)
        reading_id = str(reading.id)

    # Push to open WebSocket so the live glucose card refreshes immediately.
    # Interim mechanism — the old /ws/glucose endpoint's own manager, kept
    # until it's retired in favor of the fanout hub's /ws/app/stream (Phase B).
    await manager.send_reading(
        user_id=str(current_user.id),
        reading={
            "type":          "MANUAL_READING",
            "value":         request.value_mgdl,
            "timestamp":     recorded_at.isoformat(),
            "trend_arrow":   "→",
            "is_live":       False,
            "is_continuous": False,
            "alerts":        _check_alerts(request.value_mgdl, str(current_user.id), db),
        },
    )

    # Publish through the fanout hub too (architecture-v3.md §2.6) — a
    # manual entry must be indistinguishable downstream from a Libre one:
    # same glucose.reading shape, just source="MANUAL" and no sensor_id.
    fanout_hub.publish_glucose_reading(
        current_user.id,
        recorded_at=recorded_at,
        mgdl=request.value_mgdl,
        trend=None,
        trend_arrow="→",
        sensor_id=None,
        source="MANUAL",
    )

    return {"success": True, "reading_id": reading_id}
