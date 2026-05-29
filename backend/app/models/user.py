import uuid
from sqlalchemy import Column, Integer, String, Float, Boolean, Date, DateTime, ForeignKey, text, Numeric
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from ..database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    email = Column(String, unique=True, nullable=False)
    password_hash = Column(String, nullable=False)
    name = Column(String)
    dob = Column(Date)
    gender = Column(String)
    weight_kg = Column(Numeric(5, 2))
    height_cm = Column(Numeric(5, 2))
    diabetes_type = Column(String) # 'T1', 'T2', 'PRE'
    created_at = Column(DateTime, server_default=text("now()"))
    consent_confirmed_at = Column(DateTime)

    insulin_profiles = relationship("InsulinProfile", back_populates="user")
    cgm_devices = relationship("CGMDevice", back_populates="user")
    wearable_devices = relationship("WearableDevice", back_populates="user")
    lifestyle_baselines = relationship("LifestyleBaseline", back_populates="user")

class InsulinProfile(Base):
    __tablename__ = "insulin_profiles"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    icr = Column(Numeric(5, 2))
    isf = Column(Numeric(6, 2))
    basal_rate = Column(Numeric(5, 3))
    target_glucose_min = Column(Integer)
    target_glucose_max = Column(Integer)
    insulin_type = Column(String)
    profile_complete = Column(Boolean, server_default=text("false"))
    created_at = Column(DateTime, server_default=text("now()"))
    updated_at = Column(DateTime, server_default=text("now()"))

    user = relationship("User", back_populates="insulin_profiles")

class CGMDevice(Base):
    __tablename__ = "cgm_devices"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    device_type = Column(String)        # 'DEXCOM_G6', 'LIBRE_2', etc.
    is_active = Column(Boolean, server_default=text("true"))
    is_continuous = Column(Boolean, server_default=text("true"))   # False for BGMs
    supports_trend = Column(Boolean, server_default=text("true"))  # False for BGMs
    connected_at = Column(DateTime, server_default=text("now()"))
    deleted_at = Column(DateTime)       # For soft-delete
    
    # Sensor status fields
    sensor_status = Column(String)      # 'ACTIVE', 'EXPIRED', 'WARMING_UP', etc.
    sensor_expiry_date = Column(DateTime)
    last_sync_at = Column(DateTime)

    user = relationship("User", back_populates="cgm_devices")

class WearableDevice(Base):
    __tablename__ = "wearable_devices"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    device_type = Column(String)        # 'FITBIT', 'GARMIN', 'APPLE_HEALTH', 'GOOGLE_FIT'
    is_active = Column(Boolean, server_default=text("true"))
    connected_at = Column(DateTime, server_default=text("now()"))
    deleted_at = Column(DateTime)
    last_sync_at = Column(DateTime)

    user = relationship("User", back_populates="wearable_devices")

class LifestyleBaseline(Base):
    __tablename__ = "lifestyle_baselines"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    baseline_sleep_hrs = Column(Numeric(3, 1))
    baseline_activity_level = Column(String) # 'SEDENTARY', etc.
    baseline_stress_level = Column(String) # 'LOW', etc.
    baseline_calories = Column(Integer)
    recorded_at = Column(DateTime, server_default=text("now()"))

    user = relationship("User", back_populates="lifestyle_baselines")
