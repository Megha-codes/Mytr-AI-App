"""Realtime envelope: the versioned frame shape from architecture-v3.md §2.6.

Every frame sent over the future `/ws/app/stream` and `/ws/device/stream`
endpoints (Phase B) shares this envelope: `{v, type, ts, seq, data}`. This
module only builds envelopes and their `data` payloads — the transport
(websocket endpoints) doesn't exist yet in this phase; FanoutHub is the only
thing constructing frames today, and it's tested directly with no websocket
involved.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

ENVELOPE_VERSION = 1

# Frame types built and published in this phase.
FRAME_TYPE_HELLO = "hello"
FRAME_TYPE_GLUCOSE_READING = "glucose.reading"
FRAME_TYPE_GLUCOSE_STATE = "glucose.state"
FRAME_TYPE_PING = "ping"

# Defined per §2.6 but not yet built or published — later phases wire these
# up (health samples batch, meal log/delete, app-initiated device commands).
FRAME_TYPE_HEALTH_UPDATED = "health.updated"
FRAME_TYPE_CALORIES_UPDATED = "calories.updated"
FRAME_TYPE_DEVICE_COMMAND = "device.command"

# Not an envelope — §2.6's client/hub control messages are bare, un-versioned
# `{"type": ...}` markers, not `{v, type, ts, seq, data}` frames.
CLIENT_FRAME_TYPE_RESUME = "resume"
RESYNC_FRAME: dict = {"type": "resync"}

HEARTBEAT_SECONDS = 30


def build_envelope(type_: str, seq: int, data: dict, ts: Optional[datetime] = None) -> dict:
    ts = ts or datetime.now(timezone.utc)
    return {"v": ENVELOPE_VERSION, "type": type_, "ts": int(ts.timestamp()), "seq": seq, "data": data}


def build_hello_data(seq: int, heartbeat_s: int = HEARTBEAT_SECONDS) -> dict:
    return {
        "server_time": datetime.now(timezone.utc).isoformat(),
        "seq": seq,
        "heartbeat_s": heartbeat_s,
    }


def build_glucose_reading_data(
    ts: datetime,
    mgdl: int,
    trend: Optional[str],
    trend_arrow: Optional[str],
    sensor_id: Optional[str],
    source: str,
) -> dict:
    return {
        "ts": int(ts.timestamp()),
        "mgdl": mgdl,
        "trend": trend,
        "trend_arrow": trend_arrow,
        "sensor_id": sensor_id,
        "source": source,
    }


def build_glucose_state_data(state: str, since: datetime) -> dict:
    return {"state": state, "since": since.isoformat()}
