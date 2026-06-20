from sqlalchemy import Column, Integer, Date, DateTime, ForeignKey, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from ..database import Base


class ActivityLog(Base):
    __tablename__ = "activity_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    date = Column(Date, nullable=False, server_default=text("CURRENT_DATE"))
    steps_today = Column(Integer, nullable=False, default=0)
    calories_burned = Column(Integer, nullable=False, default=0)
    heart_rate = Column(Integer, nullable=False, default=0)
    synced_at = Column(DateTime(timezone=True), server_default=text("now()"))

    user = relationship("User", back_populates="activity_logs")
