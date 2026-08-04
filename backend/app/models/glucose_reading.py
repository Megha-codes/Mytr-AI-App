from sqlalchemy import Column, Integer, String, Boolean, Index, PrimaryKeyConstraint, text, DateTime
from sqlalchemy.dialects.postgresql import UUID
from ..timescale_database import TimescaleBase


class GlucoseReadingModel(TimescaleBase):
    __tablename__ = "glucose_readings"
    __table_args__ = (
        PrimaryKeyConstraint("id", "recorded_at"),
        # Idempotent ingestion (architecture-v3.md §1.3): the shared poller
        # re-fetches overlapping graph windows every cycle, so writes go
        # through ON CONFLICT DO NOTHING against this index. Mirrors
        # migrations/011_glucose_dedup_and_region.sql — declared here too so
        # it's real, testable metadata rather than only living in raw SQL.
        Index(
            "glucose_readings_dedup_idx",
            "user_id", "sensor_id", "recorded_at",
            unique=True,
            postgresql_where=text("sensor_id IS NOT NULL"),
            sqlite_where=text("sensor_id IS NOT NULL"),
        ),
    )

    id = Column(UUID(as_uuid=True), server_default=text("gen_random_uuid()"), nullable=False)
    user_id = Column(UUID(as_uuid=True), nullable=False)
    value_mgdl = Column(Integer, nullable=False)
    trend = Column(String)
    trend_arrow = Column(String)
    device_type = Column(String)
    is_continuous = Column(Boolean)
    recorded_at = Column(DateTime(timezone=True), nullable=False)
    sensor_id = Column(String)
    source = Column(String, nullable=False, server_default=text("'LIBRE'"))  # 'LIBRE' | 'MANUAL' | 'ACCUCHEK'
