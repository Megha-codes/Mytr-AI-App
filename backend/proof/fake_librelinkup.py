"""A minimal fake LibreLinkUp API for the offline end-to-end proof.

Speaks just enough of the real contract for the poller: POST /llu/auth/login,
GET /llu/connections, GET /llu/connections/{id}/graph. Every reading carries a
genuine US-style, timezone-less ``Timestamp`` string ("6/9/2024 3:45:12 PM") in
a configured local timezone, so the proof exercises the real parse-to-UTC path.

Readings are revealed *gradually* (a step per /graph call), mirroring the mock
server's publish clock: a real backend only knows about readings up to "now".
This is what lets the proof open a stream, force a disconnect, keep producing
readings while disconnected, then show syncd's backfill recover them with zero
gaps and zero duplicates.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import FastAPI

# Deterministic dataset the fake reveals over time.
TOTAL_READINGS = 40
REVEAL_STEP = 4               # readings newly revealed per /graph call
INTERVAL_MIN = 1             # spacing between readings
LOCAL_TZ = "Asia/Kolkata"    # the "account timezone" (UTC+5:30) the strings are in
SENSOR_SN = "sensor-PROOF-01"
PATIENT_ID = "patient-proof-1"
# Base wall-clock time in LOCAL_TZ for reading[0].
BASE_LOCAL = datetime(2024, 6, 9, 15, 45, 12)

_TREND_CYCLE = [3, 4, 5, 4, 3, 2, 1, 2]  # exercises every TrendArrow code


def _fmt_us(dt: datetime) -> str:
    """Format as M/D/YYYY H:MM:SS AM/PM with no leading zeros (Libre style)."""
    hour12 = dt.hour % 12 or 12
    ampm = "AM" if dt.hour < 12 else "PM"
    return f"{dt.month}/{dt.day}/{dt.year} {hour12}:{dt.minute:02d}:{dt.second:02d} {ampm}"


def build_dataset() -> list[dict]:
    readings = []
    for i in range(TOTAL_READINGS):
        local_dt = BASE_LOCAL + timedelta(minutes=INTERVAL_MIN * i)
        readings.append(
            {
                "Timestamp": _fmt_us(local_dt),
                "ValueInMgPerDl": 100 + (i % 25),
                "TrendArrow": _TREND_CYCLE[i % len(_TREND_CYCLE)],
            }
        )
    return readings


def expected_epoch(i: int) -> int:
    """The UTC epoch the poller *should* store for reading i (independent calc)."""
    local_dt = (BASE_LOCAL + timedelta(minutes=INTERVAL_MIN * i)).replace(
        tzinfo=ZoneInfo(LOCAL_TZ)
    )
    return int(local_dt.timestamp())


def create_app() -> FastAPI:
    app = FastAPI(title="fake-librelinkup")
    dataset = build_dataset()
    state = {"revealed": 0}

    @app.post("/llu/auth/login")
    async def login():
        return {"data": {"authTicket": {"token": "fake-token"}, "user": {"id": "fake-user-id"}}}

    @app.get("/llu/connections")
    async def connections():
        return {
            "data": [
                {
                    "patientId": PATIENT_ID,
                    "firstName": "Proof",
                    "lastName": "Sensor",
                    "sensor": {"sn": SENSOR_SN},
                    "alarmRules": {"low": 70, "high": 180},
                }
            ]
        }

    @app.get("/llu/connections/{patient_id}/graph")
    async def graph(patient_id: str):
        state["revealed"] = min(state["revealed"] + REVEAL_STEP, TOTAL_READINGS)
        return {"data": {"graphData": dataset[: state["revealed"]]}}

    return app


app = create_app()
