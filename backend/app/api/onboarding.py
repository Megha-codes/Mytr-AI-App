from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from ..schemas.user import UserOnboardRequest, AuthResponse
from ..models.user import User, InsulinProfile, LifestyleBaseline, CGMDevice
from ..database import get_db
from datetime import datetime, timezone

from ..core.security import create_access_token, create_refresh_token, get_password_hash

router = APIRouter()

@router.post("/onboard", response_model=AuthResponse)
async def onboard_user(request: UserOnboardRequest, db: AsyncSession = Depends(get_db)):
    try:
        result = await db.execute(select(User).where(User.email == request.email))
        existing_user = result.scalar_one_or_none()
        if existing_user:
            raise HTTPException(status_code=409, detail="An account with this email already exists.")

        password_hash = get_password_hash(request.password)

        user = User(
            email=request.email,
            password_hash=password_hash,
            name=request.name,
            dob=request.dob,
            gender=request.gender,
            weight_kg=request.weight_kg,
            height_cm=request.height_cm,
            diabetes_type=request.diabetes_type,
            consent_confirmed_at=request.consent_confirmed_at or datetime.now(timezone.utc)
        )
        db.add(user)
        await db.flush()

        if request.icr is not None:
            db.add(InsulinProfile(
                user_id=user.id,
                icr=request.icr,
                isf=request.isf,
                basal_rate=request.basal_rate,
                target_glucose_min=request.target_glucose_min,
                target_glucose_max=request.target_glucose_max,
                insulin_type=request.insulin_type,
                profile_complete=False
            ))

        if request.avg_sleep is not None:
            try:
                sleep_hrs = float(request.avg_sleep)
            except (ValueError, TypeError):
                sleep_hrs = None

            db.add(LifestyleBaseline(
                user_id=user.id,
                baseline_sleep_hrs=sleep_hrs,
                baseline_activity_level=request.activity_level,
                baseline_stress_level=request.stress_level
            ))

        if request.cgm_device is not None:
            db.add(CGMDevice(
                user_id=user.id,
                device_type=request.cgm_device,
                is_active=True,
                is_continuous=True,
                supports_trend=True
            ))

        await db.commit()
        await db.refresh(user)

        return AuthResponse(
            access_token=create_access_token(str(user.id)),
            refresh_token=create_refresh_token(str(user.id)),
            user_id=user.id
        )

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to onboard user: {str(e)}")
