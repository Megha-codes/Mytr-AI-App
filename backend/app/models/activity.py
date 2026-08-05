from sqlalchemy import Column, Index, Integer, Date, DateTime, ForeignKey, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from ..database import Base


class ActivityLog(Base):
    __tablename__ = "activity_logs"
    __table_args__ = (
        # One row per user per day (migrations/009_activity_sync.sql); both
        # POST /activity/sync and the health_metrics projection recompute
        # upsert against this index.
        Index("activity_logs_user_date_idx", "user_id", "date", unique=True),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    date = Column(Date, nullable=False, server_default=text("CURRENT_DATE"))
    steps_today = Column(Integer, nullable=False, default=0)
    calories_burned = Column(Integer, nullable=False, default=0)
    heart_rate = Column(Integer, nullable=False, default=0)
    synced_at = Column(DateTime(timezone=True), server_default=text("now()"))

    user = relationship("User", back_populates="activity_logs")
