"""GET /analytics/weekly (Phase-1 polish, part 2): glucose TIR/GMI/trend,
the food-glucose correlation feature, health metric trends, and nutrition
trends, all in one call so the analytics screen loads with a single
request instead of five."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.user import User
from ..schemas.analytics import WeeklyAnalyticsResponse
from ..services.analytics.weekly import DEFAULT_WINDOW_DAYS, build_weekly_analytics
from .auth import get_current_user

router = APIRouter()


@router.get("/analytics/weekly", response_model=WeeklyAnalyticsResponse)
async def get_weekly_analytics(
    days: int = Query(DEFAULT_WINDOW_DAYS, ge=2, le=30),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await build_weekly_analytics(
        db, current_user.id, current_user.timezone, window_days=days,
    )
