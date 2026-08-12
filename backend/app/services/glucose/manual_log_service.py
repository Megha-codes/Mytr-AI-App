"""Shared manual-glucose-logging logic: insert one reading, fan it out
live. Used by both POST /glucose/manual (app/api/glucose.py) and the
analytics chatbot's log_manual_glucose tool (services/chat/tools.py) --
one real implementation, so a manual entry from the chat is
indistinguishable downstream (live stream, TIR, correlations) from one
entered through the form.
"""

from __future__ import annotations

from datetime import datetime, timezone

from ...models.glucose_reading import GlucoseReadingModel
from ...timescale_database import TimescaleSessionLocal
from ..realtime.fanout_hub import fanout_hub


async def log_manual_glucose_reading(user_id, value_mgdl: int, timestamp: datetime) -> str:
    """Raises ValueError on an out-of-range value -- callers translate
    that to whatever's appropriate for their surface (a 400 for the HTTP
    route, a {"error": ...} tool result for the chatbot)."""
    if not 40 <= value_mgdl <= 400:
        raise ValueError("Glucose value out of valid range (40–400 mg/dL)")

    recorded_at = timestamp
    if recorded_at.tzinfo is None:
        recorded_at = recorded_at.replace(tzinfo=timezone.utc)

    async with TimescaleSessionLocal() as ts_session:
        reading = GlucoseReadingModel(
            user_id=user_id,
            value_mgdl=value_mgdl,
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
        user_id,
        recorded_at=recorded_at,
        mgdl=value_mgdl,
        trend=None,
        trend_arrow="→",
        sensor_id=None,
        source="MANUAL",
    )

    return reading_id
