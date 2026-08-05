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

    # Push to every live subscriber via the fanout hub (architecture-v3.md
    # §2.6) — /ws/glucose's own manager is retired now that /ws/app/stream
    # exists. A manual entry must be indistinguishable downstream from a
    # Libre one: same glucose.reading shape, just source="MANUAL" and no
    # sensor_id.
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
