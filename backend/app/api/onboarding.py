from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ..schemas.user import UserOnboardRequest, AuthResponse
from ..models.user import User, InsulinProfile, LifestyleBaseline, CGMDevice
from ..database import get_db
import uuid
from datetime import datetime

from ..core.security import create_access_token, create_refresh_token, get_password_hash

router = APIRouter()

@router.post("/onboard", response_model=AuthResponse)
def onboard_user(request: UserOnboardRequest, db: Session = Depends(get_db)):
    """
    Endpoint to save user onboarding data and return tokens.
    """
    try:
        # Check if email already exists
        existing_user = db.query(User).filter(User.email == request.email).first()
        if existing_user:
            raise HTTPException(status_code=409, detail="An account with this email already exists.")

        # Hash the provided password
        password_hash = get_password_hash(request.password)

        # Create User
        user = User(
            email=request.email,
            password_hash=password_hash,
            name=request.name,
            dob=request.dob,
            gender=request.gender,
            weight_kg=request.weight_kg,
            height_cm=request.height_cm,
            diabetes_type=request.diabetes_type,
            consent_confirmed_at=request.consent_confirmed_at or datetime.utcnow()
        )
        db.add(user)
        db.flush() # To get user.id
        
        # Create InsulinProfile if icr is provided
        if request.icr is not None:
            ip = InsulinProfile(
                user_id=user.id,
                icr=request.icr,
                isf=request.isf,
                basal_rate=request.basal_rate,
                target_glucose_min=request.target_glucose_min,
                target_glucose_max=request.target_glucose_max,
                insulin_type=request.insulin_type,
                profile_complete=False
            )
            db.add(ip)

        # Create LifestyleBaseline if avg_sleep is provided
        if request.avg_sleep is not None:
            try:
                sleep_hrs = float(request.avg_sleep)
            except (ValueError, TypeError):
                sleep_hrs = None
                
            lb = LifestyleBaseline(
                user_id=user.id,
                baseline_sleep_hrs=sleep_hrs,
                baseline_activity_level=request.activity_level,
                baseline_stress_level=request.stress_level
            )
            db.add(lb)

        # Create CGMDevice if cgm_device is provided
        if request.cgm_device is not None:
            cgm = CGMDevice(
                user_id=user.id,
                device_type=request.cgm_device,
                is_active=True,
                is_continuous=True,
                supports_trend=True
            )
            db.add(cgm)

        db.commit()
        db.refresh(user)

        # Generate tokens
        access_token = create_access_token(str(user.id))
        refresh_token = create_refresh_token(str(user.id))

        return AuthResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            user_id=user.id
        )

    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to onboard user: {str(e)}")
