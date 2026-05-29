import uuid
from sqlalchemy import Column, String, Float, Boolean, DateTime, ForeignKey, text, Numeric
from sqlalchemy.dialects.postgresql import UUID, JSONB, ARRAY
from sqlalchemy.orm import relationship
from ..database import Base

class RecommendationAuditLog(Base):
    __tablename__ = "recommendation_audit_log"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    recommended_dose_units = Column(Numeric(5, 2))
    base_bolus = Column(Numeric(5, 2))
    correction_dose = Column(Numeric(5, 2))
    lifestyle_adjustment_pct = Column(Numeric(5, 1))
    confidence_score = Column(Numeric(3, 2))
    feature_vector = Column(JSONB)
    model_version = Column(String)
    recommendation_drivers = Column(ARRAY(String))
    show_doctor_flag = Column(Boolean)
    created_at = Column(DateTime, server_default=text("now()"))

    user = relationship("User", backref="audit_logs")
