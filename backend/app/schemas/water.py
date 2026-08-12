"""Schemas for POST /water/log, GET /water/daily, and their device twin
(architecture-v3.md-style: user-JWT + device-JWT pair, matching /health/daily
and /device/health/daily). Water is stored as an ordinary health_metrics
row (metric='water_ml') -- see services/health/daily_rollup.py's
_AGGREGATION -- not a dedicated table; these are thin, purpose-built
endpoints on top of that shared store for a quick-log UI, not a new
storage layer.
"""

from __future__ import annotations

from datetime import date as date_type
from typing import Optional

from pydantic import BaseModel, Field


class WaterLogRequest(BaseModel):
    # A single quick-add entry, not a bulk/historical import -- 2000ml
    # (a full daily goal in one entry) is already a generous upper bound.
    amount_ml: int = Field(..., gt=0, le=2000)


class WaterLogResponse(BaseModel):
    success: bool
    total_ml_today: int


class WaterDailyResponse(BaseModel):
    date: date_type
    # None (not 0) when nothing has been logged that day at all -- same
    # null-vs-zero convention as every other daily metric in this app.
    total_ml: Optional[int] = None
    goal_ml: int
