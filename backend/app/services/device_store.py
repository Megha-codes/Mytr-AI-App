"""Persistence for device-pipeline readings.

Writes from the Libre poller and reads for the /v1/readings backfill both go
through here. Dedup is on (sensor_id, ts): the poller re-pulls overlapping ~12h
graph windows every minute, and ``insert_readings`` returns only the rows that
were genuinely new so the caller publishes each reading to the stream exactly
once. Kept backend-agnostic (portable SQL only) so it runs on the SQLite store
used by the offline proof and tests as well as production Postgres.
"""

from __future__ import annotations

from sqlalchemy import select

from ..device_database import DeviceSessionLocal
from ..models.device import DeviceReading


class DeviceStore:
    def __init__(self, sessionmaker=DeviceSessionLocal) -> None:
        self._sessionmaker = sessionmaker

    async def insert_readings(self, readings: list[dict]) -> list[dict]:
        """Insert readings, skipping any (sensor_id, ts) already stored.

        Returns the subset that was actually inserted, in ascending ts order —
        the caller publishes exactly these to the live stream.
        """
        if not readings:
            return []

        async with self._sessionmaker() as session:
            # Filter out already-stored keys per sensor (single-writer poller,
            # so no insert race to guard against here).
            by_sensor: dict[str, set[int]] = {}
            for r in readings:
                by_sensor.setdefault(r["sensor_id"], set()).add(int(r["ts"]))

            existing: set[tuple[str, int]] = set()
            for sensor_id, ts_values in by_sensor.items():
                rows = await session.execute(
                    select(DeviceReading.ts).where(
                        DeviceReading.sensor_id == sensor_id,
                        DeviceReading.ts.in_(ts_values),
                    )
                )
                existing.update((sensor_id, int(ts)) for (ts,) in rows.all())

            # De-dup within the batch too, then keep only genuinely-new rows.
            new: list[dict] = []
            seen: set[tuple[str, int]] = set()
            for r in readings:
                key = (r["sensor_id"], int(r["ts"]))
                if key in existing or key in seen:
                    continue
                seen.add(key)
                new.append(r)

            for r in new:
                session.add(
                    DeviceReading(
                        ts=int(r["ts"]),
                        mgdl=float(r["mgdl"]),
                        trend=r.get("trend"),
                        sensor_id=r["sensor_id"],
                    )
                )
            await session.commit()

        new.sort(key=lambda r: r["ts"])
        return new

    async def get_readings_since(self, since_ts: int) -> list[dict]:
        """All readings with ts > since_ts, ascending — the backfill query."""
        async with self._sessionmaker() as session:
            rows = await session.execute(
                select(
                    DeviceReading.ts,
                    DeviceReading.mgdl,
                    DeviceReading.trend,
                    DeviceReading.sensor_id,
                )
                .where(DeviceReading.ts > since_ts)
                .order_by(DeviceReading.ts.asc())
            )
        return [
            {"ts": int(ts), "mgdl": float(mgdl), "trend": trend, "sensor_id": sensor_id}
            for ts, mgdl, trend, sensor_id in rows.all()
        ]


# Shared default store used by the API routes and the startup poller.
store = DeviceStore()
