from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, Numeric, String
from sqlalchemy.dialects.postgresql import JSONB, UUID

from ..database import Base


class MealLog(Base):
    __tablename__ = "meal_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default="gen_random_uuid()")
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    meal_time = Column(DateTime(timezone=True), nullable=False)

    # Food identification
    food_items = Column(JSONB, nullable=False)
    recognition_confidence = Column(Numeric(3, 2))
    user_corrected = Column(Boolean, default=False)
    user_correction_notes = Column(String, nullable=True)

    # Nutritional totals
    total_calories = Column(Integer)
    total_carbs_g = Column(Numeric(6, 1))
    total_protein_g = Column(Numeric(6, 1))
    total_fat_g = Column(Numeric(6, 1))
    total_fiber_g = Column(Numeric(6, 1), default=0)
    glycaemic_load = Column(Numeric(5, 1))

    # Bolus recommendation
    recommendation_id = Column(
        UUID(as_uuid=True), ForeignKey("recommendation_audit_log.id"), nullable=True
    )

    # Post-meal outcome
    post_meal_glucose_1hr = Column(Integer, nullable=True)
    post_meal_glucose_2hr = Column(Integer, nullable=True)
    glucose_outcome = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
