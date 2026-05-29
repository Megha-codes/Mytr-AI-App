from datetime import datetime, timedelta
from uuid import UUID as PUUID
from sqlalchemy import select, and_, desc
from .factory import BaseCGMService, CGMReading


class ManualGlucoseService(BaseCGMService):
    """Reads manual glucose entries logged via POST /glucose/manual from TimescaleDB."""
    is_continuous = False
    supports_trend = False

    async def get_latest_reading(self, user_id: str) -> CGMReading | None:
        from ...timescale_database import TimescaleSessionLocal
        from ...models.glucose_reading import GlucoseReadingModel

        try:
            async with TimescaleSessionLocal() as session:
                result = await session.execute(
                    select(GlucoseReadingModel)
                    .where(GlucoseReadingModel.user_id == PUUID(user_id))
                    .where(GlucoseReadingModel.device_type == "MANUAL")
                    .order_by(desc(GlucoseReadingModel.recorded_at))
                    .limit(1)
                )
                row = result.scalars().first()

            if row is None:
                return None

            return CGMReading(
                value=row.value_mgdl,
                timestamp=row.recorded_at.replace(tzinfo=None),
                trend="NONE",
                trend_arrow="→",
                device_type="MANUAL",
                is_continuous=False,
            )
        except Exception:
            return None

    async def get_reading_at_time(
        self,
        user_id: str,
        target_time: datetime,
        tolerance_minutes: int = 10,
    ) -> CGMReading | None:
        from ...timescale_database import TimescaleSessionLocal
        from ...models.glucose_reading import GlucoseReadingModel

        window_start = target_time - timedelta(minutes=tolerance_minutes)
        window_end   = target_time + timedelta(minutes=tolerance_minutes)

        try:
            async with TimescaleSessionLocal() as session:
                result = await session.execute(
                    select(GlucoseReadingModel)
                    .where(
                        and_(
                            GlucoseReadingModel.user_id       == PUUID(user_id),
                            GlucoseReadingModel.device_type   == "MANUAL",
                            GlucoseReadingModel.recorded_at   >= window_start,
                            GlucoseReadingModel.recorded_at   <= window_end,
                        )
                    )
                    .order_by(desc(GlucoseReadingModel.recorded_at))
                    .limit(1)
                )
                row = result.scalars().first()

            if row is None:
                return None

            return CGMReading(
                value=row.value_mgdl,
                timestamp=row.recorded_at.replace(tzinfo=None),
                trend="NONE",
                trend_arrow="→",
                device_type="MANUAL",
                is_continuous=False,
            )
        except Exception:
            return None
