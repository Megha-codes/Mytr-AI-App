from pydantic import BaseModel
from typing import Optional
from uuid import UUID
from datetime import datetime

class UserContextSchema(BaseModel):
    user_id: UUID
    diabetes_type: Optional[str] = None
    weight_kg: Optional[float] = None
    icr: Optional[float] = None
    isf: Optional[float] = None
    basal_rate: Optional[float] = None
    target_glucose_min: Optional[int] = None
    target_glucose_max: Optional[int] = None
    insulin_type: Optional[str] = None
    cgm_device: Optional[str] = None
    baseline_sleep_hrs: Optional[float] = None
    baseline_activity_level: Optional[str] = None
    baseline_stress_level: Optional[str] = None
    baseline_calories: Optional[int] = None

class BolusRequest(BaseModel):
    user_id: UUID
    
    # Meal inputs
    carbs_g: float
    meal_glycaemic_load: float
    
    # Real-time signals
    current_glucose_mgdl: float
    last_activity_minutes_ago: int
    last_activity_duration_mins: int
    last_activity_intensity: str
    last_sleep_hrs: float
    current_stress_level: str
    
    # Time context
    meal_time: datetime
    time_since_last_bolus_hrs: float
