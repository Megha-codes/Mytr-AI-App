from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import date, datetime
from uuid import UUID

class InsulinProfileSchema(BaseModel):
    icr: Optional[float] = None
    isf: Optional[float] = None
    basal_rate: Optional[float] = None
    target_glucose_min: Optional[int] = None
    target_glucose_max: Optional[int] = None
    insulin_type: Optional[str] = None
    profile_complete: bool = False

class LifestyleBaselineSchema(BaseModel):
    sleep_hrs: Optional[str] = None
    activity_level: Optional[str] = None
    stress_level: Optional[str] = None
    calorie_intake: Optional[str] = None

class DeviceSetupSchema(BaseModel):
    cgm_device: Optional[str] = None
    manual_entry: bool = False
    wearables: List[str] = Field(default_factory=list)

class UserOnboardRequest(BaseModel):
    user_type: str
    email: str
    password: str
    name: str
    dob: Optional[date] = None
    gender: Optional[str] = None
    weight_kg: Optional[float] = None
    height_cm: Optional[float] = None
    primary_goal: Optional[str] = None
    
    diabetes_type: Optional[str] = None
    icr: Optional[float] = None
    isf: Optional[float] = None
    basal_rate: Optional[float] = None
    target_glucose_min: Optional[int] = None
    target_glucose_max: Optional[int] = None
    insulin_type: Optional[str] = None
    
    cgm_device: Optional[str] = None
    
    avg_sleep: Optional[str] = None
    activity_level: Optional[str] = None
    stress_level: Optional[str] = None
    
    consent_confirmed_at: Optional[datetime] = None
    research_consent: Optional[bool] = True

class AuthResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: UUID

class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: str
    user_type: Optional[str] = None
    name: Optional[str] = None

class UserProfileResponse(BaseModel):
    id: str
    name: Optional[str] = None
    email: str
    user_type: Optional[str] = None
    diabetes_type: Optional[str] = None
    onboarding_complete: bool

