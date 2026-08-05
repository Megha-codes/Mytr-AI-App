"""Daily health rollup (architecture-v3.md §1.4 / §2.4 / §2.5): aggregates
health_metrics into a single day's summary. Shared by GET /health/daily
(user-JWT), GET /device/health/daily (device-JWT), GET /device/snapshot's
health sub-object, and the activity_logs projection recompute.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import date as date_type, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...models.health_metric import HealthMetric

# How each metric aggregates across a day's samples: "sum" for cumulative
# counters, "avg" for point-in-time rate metrics, "last" for a
# once-a-day-ish measurement. The schema is metric-agnostic (§1.4), but the
# rollup still needs *some* strategy per metric — an unrecognized one
# defaults to "avg", since summing an unknown rate-like metric is wrong far
# more often than averaging an unknown cumulative one is merely imprecise.
_AGGREGATION = {
    "steps": "sum",
    "active_energy_kcal": "sum",
    "sleep_minutes": "sum",
    "heart_rate": "avg",
    "resting_heart_rate": "avg",
    "hrv": "avg",
    "weight_kg": "last",
}
_DEFAULT_AGGREGATION = "avg"


def _resolve_zone(tz_name: str):
    try:
        return ZoneInfo(tz_name)
    except (ZoneInfoNotFoundError, ValueError):
        return timezone.utc


async def compute_daily_rollup(
    db: AsyncSession, user_id, target_date: date_type, user_timezone: str = "UTC"
) -> dict:
    """Returns `{metric_name: aggregated_value, ..., "updated_at": datetime}`
    for whichever metrics have at least one sample within `target_date` (a
    full local day in `user_timezone`, converted to UTC for the query since
    `started_at` is stored tz-aware). A metric with zero samples that day is
    simply absent from the returned dict — never zero-filled (§2.4: "0
    steps and 'no data' are different facts"). Returns `{}` when there is no
    data at all for that day.
    """
    zone = _resolve_zone(user_timezone)
    local_midnight = datetime(target_date.year, target_date.month, target_date.day, tzinfo=zone)
    range_start = local_midnight.astimezone(timezone.utc)
    range_end = (local_midnight + timedelta(days=1)).astimezone(timezone.utc)

    result = await db.execute(
        select(HealthMetric).where(
            HealthMetric.user_id == user_id,
            HealthMetric.started_at >= range_start,
            HealthMetric.started_at < range_end,
        )
    )
    samples = result.scalars().all()
    if not samples:
        return {}

    by_metric: dict[str, list[HealthMetric]] = defaultdict(list)
    for sample in samples:
        by_metric[sample.metric].append(sample)

    rollup: dict = {}
    for metric, items in by_metric.items():
        strategy = _AGGREGATION.get(metric, _DEFAULT_AGGREGATION)
        values = [item.value for item in items]
        if strategy == "sum":
            rollup[metric] = sum(values)
        elif strategy == "last":
            rollup[metric] = max(items, key=lambda i: i.started_at).value
        else:  # avg
            rollup[metric] = sum(values) / len(values)

    rollup["updated_at"] = max(sample.created_at for sample in samples)
    return rollup
