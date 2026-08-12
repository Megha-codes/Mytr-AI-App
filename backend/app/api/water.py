"""Water intake logging (Phase-1 polish, part 3). Stored as an ordinary
health_metrics row (metric='water_ml', unit='ml', source='MANUAL') --
health_metrics is explicitly metric-agnostic for exactly this reason (see
its own model docstring), so this needed no new table or migration, just
one more entry in daily_rollup.py's _AGGREGATION map.

Two endpoints, both user-JWT: POST to log a quick add, GET for today's
(or any day's) total against the daily goal. GET /device/water/daily
(app/api/device_data.py) is the device-JWT twin, same pattern as
/health/daily + /device/health/daily. The actual logic lives in
services/water/log_service.py, shared with the analytics chatbot.
"""

from __future__ import annotations

from datetime import date as date_type
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.user import User
from ..schemas.water import WaterDailyResponse, WaterLogRequest, WaterLogResponse
from ..services.water.log_service import DEFAULT_WATER_GOAL_ML, get_water_summary, log_water_entry
from .auth import get_current_user

router = APIRouter()


@router.post("/water/log", response_model=WaterLogResponse, status_code=201)
async def log_water(
    request: WaterLogRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    total = await log_water_entry(db, current_user, request.amount_ml)
    return WaterLogResponse(success=True, total_ml_today=total)


@router.get("/water/daily", response_model=WaterDailyResponse)
async def get_water_daily(
    date: Optional[date_type] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await get_water_summary(db, current_user, date)
