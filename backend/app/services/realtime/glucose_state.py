"""Resolves the device-facing glucose `state` (architecture-v3.md §2.4) —
load-bearing: the device renders a distinct screen per value and must never
substitute a number for missing/stale data.

    LIVE          reading < 10 min old
    STALE         newest reading >= 10 min old
    NO_SENSOR     an active CGM connection exists but has no current reading
                  (sensor expired, or none ingested yet)
    NOT_CONNECTED user has no active CGM connection in the app at all
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

LIVE_THRESHOLD = timedelta(minutes=10)

STATE_LIVE = "LIVE"
STATE_STALE = "STALE"
STATE_NO_SENSOR = "NO_SENSOR"
STATE_NOT_CONNECTED = "NOT_CONNECTED"


def resolve_glucose_state(cgm_device, latest_reading, now: Optional[datetime] = None) -> str:
    if cgm_device is None or not cgm_device.is_active:
        return STATE_NOT_CONNECTED
    if cgm_device.sensor_status == "EXPIRED" or latest_reading is None:
        return STATE_NO_SENSOR

    now = now or datetime.now(timezone.utc)
    recorded_at = latest_reading.recorded_at
    if recorded_at.tzinfo is None:
        recorded_at = recorded_at.replace(tzinfo=timezone.utc)
    age = now - recorded_at
    return STATE_LIVE if age < LIVE_THRESHOLD else STATE_STALE
