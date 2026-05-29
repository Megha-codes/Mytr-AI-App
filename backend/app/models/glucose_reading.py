from sqlalchemy import Column, Integer, String, Boolean, PrimaryKeyConstraint, text, DateTime
from sqlalchemy.dialects.postgresql import UUID
from ..timescale_database import TimescaleBase


class GlucoseReadingModel(TimescaleBase):
    __tablename__ = "glucose_readings"
    __table_args__ = (
        PrimaryKeyConstraint("id", "recorded_at"),
    )

    id = Column(UUID(as_uuid=True), server_default=text("gen_random_uuid()"), nullable=False)
    user_id = Column(UUID(as_uuid=True), nullable=False)
    value_mgdl = Column(Integer, nullable=False)
    trend = Column(String)
    trend_arrow = Column(String)
    device_type = Column(String)
    is_continuous = Column(Boolean)
    recorded_at = Column(DateTime(timezone=True), nullable=False)
