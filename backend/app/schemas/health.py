"""Schemas for POST /api/v1/health/samples and GET /api/v1/health/daily
(architecture-v3.md §1.4 / §2.5).
"""

from __future__ import annotations

from datetime import date as date_type, datetime
from typing import Optional

from pydantic import BaseModel, Field


class HealthSampleIn(BaseModel):
    metric: str
    value: float
    unit: str
    started_at: datetime
    ended_at: datetime
    source: str
    external_id: Optional[str] = None


class HealthSamplesRequest(BaseModel):
    # architecture-v3.md §2.5: "Max 1000/request."
    samples: list[HealthSampleIn] = Field(..., max_length=1000)


class HealthSamplesResponse(BaseModel):
    accepted: int
    duplicates: int


class HealthDailyResponse(BaseModel):
    date: date_type
    steps: Optional[float] = None
    active_energy_kcal: Optional[float] = None
    heart_rate: Optional[float] = None
    resting_heart_rate: Optional[float] = None
    sleep_minutes: Optional[float] = None
    hrv: Optional[float] = None
    updated_at: Optional[datetime] = None
