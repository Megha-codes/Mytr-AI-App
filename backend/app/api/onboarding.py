from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from ..schemas.user import UserOnboardRequest, AuthResponse
from ..models.user import User, InsulinProfile, LifestyleBaseline, CGMDevice
from ..database import get_db
from datetime import datetime, timezone

import logging

from ..core.security import (
    create_access_token,
    create_refresh_token,
    create_verify_token,
    get_password_hash,
)
from ..core.password_policy import validate_password
from ..core.validators import normalize_email, is_valid_email
from ..services.email_service import send_verification_email

logger = logging.getLogger("mytr.onboarding")

router = APIRouter()

@router.post("/onboard", response_model=AuthResponse)
async def onboard_user(request: UserOnboardRequest, db: AsyncSession = Depends(get_db)):
    try:
        if not is_valid_email(request.email):
            raise HTTPException(status_code=400, detail="Please enter a valid email address.")

        password_error = validate_password(request.password)
        if password_error:
            raise HTTPException(status_code=400, detail=password_error)

        email = normalize_email(request.email)
        # Case-insensitive duplicate check so "User@x.com" and "user@x.com"
        # can't create two accounts (login already lower-cases emails).
        result = await db.execute(select(User).where(func.lower(User.email) == email))
        existing_user = result.scalar_one_or_none()
        if existing_user:
            raise HTTPException(status_code=409, detail="An account with this email already exists.")

        password_hash = get_password_hash(request.password)

        user = User(
            email=email,
            password_hash=password_hash,
            name=(request.name or "").strip() or "User",
            dob=request.dob,
            gender=request.gender,
            weight_kg=request.weight_kg,
            height_cm=request.height_cm,
            diabetes_type=request.diabetes_type,
            consent_confirmed_at=(request.consent_confirmed_at or datetime.now(timezone.utc)).replace(tzinfo=None),
            terms_accepted_at=(datetime.now(timezone.utc).replace(tzinfo=None) if request.terms_accepted else None),
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

        # Best-effort verification email — never fail signup if delivery fails.
        try:
            await send_verification_email(
                email=user.email,
                verify_token=create_verify_token(str(user.id)),
            )
        except Exception:
            logger.exception("Failed to send verification email to %s", user.email)

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
