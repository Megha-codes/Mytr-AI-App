"""Health data endpoints (architecture-v3.md §1.4 / §2.5):
POST /health/samples — batch ingest from the app's Apple Health / Health
Connect readers, and GET /health/daily — the user-JWT daily rollup.
"""

from __future__ import annotations

from datetime import date as date_type, datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.dialects import postgresql, sqlite
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.health_metric import HealthMetric
from ..models.user import User
from ..schemas.health import (
    HealthDailyResponse,
    HealthSamplesRequest,
    HealthSamplesResponse,
)
from ..services.health.activity_projection import recompute_activity_log_projection
from ..services.health.daily_rollup import compute_daily_rollup, local_date
from ..services.realtime.envelope import FRAME_TYPE_HEALTH_UPDATED
from ..services.realtime.fanout_hub import fanout_hub
from .auth import get_current_user

router = APIRouter()


def _insert_builder(dialect_name: str):
    # Same dialect switch as LibreIngestionService — production runs
    # Postgres, sqlite is the test-only stand-in.
    return sqlite.insert if dialect_name == "sqlite" else postgresql.insert


@router.post("/health/samples", response_model=HealthSamplesResponse)
async def ingest_health_samples(
    body: HealthSamplesRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not body.samples:
        return HealthSamplesResponse(accepted=0, duplicates=0)

    insert = _insert_builder(db.bind.dialect.name)
    rows = [
        {
            "user_id": current_user.id,
            "metric": sample.metric,
            "value": sample.value,
            "unit": sample.unit,
            "started_at": sample.started_at,
            "ended_at": sample.ended_at,
            "source": sample.source,
            "external_id": sample.external_id,
        }
        for sample in body.samples
    ]

    stmt = (
        insert(HealthMetric)
        .values(rows)
        .on_conflict_do_nothing(
            index_elements=["user_id", "source", "metric", "external_id"],
            index_where=text("external_id IS NOT NULL"),
        )
        # `rowcount` isn't reliable for ON CONFLICT DO NOTHING once a
        # server_default id column is involved — RETURNING is (see
        # LibreIngestionService for the same pattern).
        .returning(HealthMetric.id, HealthMetric.started_at)
    )
    result = await db.execute(stmt)
    inserted = result.all()
    accepted = len(inserted)
    duplicates = len(rows) - accepted

    affected_dates = {local_date(started_at, current_user.timezone) for _, started_at in inserted}
    for affected_date in affected_dates:
        await recompute_activity_log_projection(db, current_user.id, affected_date, current_user.timezone)

    await db.commit()

    for affected_date in affected_dates:
        fanout_hub.publish(
            current_user.id, FRAME_TYPE_HEALTH_UPDATED, {"date": affected_date.isoformat()}
        )

    return HealthSamplesResponse(accepted=accepted, duplicates=duplicates)


@router.get("/health/daily", response_model=HealthDailyResponse, response_model_exclude_none=True)
async def get_health_daily(
    date: Optional[date_type] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    target_date = date or local_date(datetime.now(timezone.utc), current_user.timezone)
    rollup = await compute_daily_rollup(db, current_user.id, target_date, current_user.timezone)
    # Splat only the fields HealthDailyResponse declares — compute_daily_rollup
    # is metric-agnostic and may return keys (e.g. weight_kg) this fixed
    # §2.4/§2.5 response shape doesn't surface.
    return HealthDailyResponse(
        date=target_date,
        steps=rollup.get("steps"),
        active_energy_kcal=rollup.get("active_energy_kcal"),
        heart_rate=rollup.get("heart_rate"),
        resting_heart_rate=rollup.get("resting_heart_rate"),
        sleep_minutes=rollup.get("sleep_minutes"),
        hrv=rollup.get("hrv"),
        updated_at=rollup.get("updated_at"),
    )
