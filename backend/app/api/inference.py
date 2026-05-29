from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from uuid import UUID

from ..database import get_db
from ..models.user import User, InsulinProfile, CGMDevice, LifestyleBaseline
from ..schemas.inference import UserContextSchema, BolusRequest
from ..services.inference_engine import build_feature_vector, inference_engine, log_recommendation

router = APIRouter()

@router.get("/users/{user_id}/context", response_model=UserContextSchema)
async def get_user_context(user_id: UUID, db: AsyncSession = Depends(get_db)):
    
    # 1. User
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # 2. Insulin Profile
    ip_result = await db.execute(
        select(InsulinProfile)
        .where(InsulinProfile.user_id == user_id)
        .where(InsulinProfile.profile_complete == True)
        .order_by(InsulinProfile.updated_at.desc())
        .limit(1)
    )
    insulin_profile = ip_result.scalars().first()

    # 3. CGM Device
    cgm_result = await db.execute(
        select(CGMDevice)
        .where(CGMDevice.user_id == user_id)
        .where(CGMDevice.is_active == True)
    )
    cgm_device = cgm_result.scalars().first()

    # 4. Lifestyle Baseline
    lifestyle_result = await db.execute(
        select(LifestyleBaseline)
        .where(LifestyleBaseline.user_id == user_id)
        .order_by(LifestyleBaseline.recorded_at.desc())
        .limit(1)
    )
    lifestyle = lifestyle_result.scalars().first()

    return UserContextSchema(
        user_id=user_id,
        diabetes_type=user.diabetes_type,
        weight_kg=float(user.weight_kg) if user.weight_kg else None,
        icr=float(insulin_profile.icr) if insulin_profile and insulin_profile.icr else None,
        isf=float(insulin_profile.isf) if insulin_profile and insulin_profile.isf else None,
        basal_rate=float(insulin_profile.basal_rate) if insulin_profile and insulin_profile.basal_rate else None,
        target_glucose_min=insulin_profile.target_glucose_min if insulin_profile else None,
        target_glucose_max=insulin_profile.target_glucose_max if insulin_profile else None,
        insulin_type=insulin_profile.insulin_type if insulin_profile else None,
        cgm_device=cgm_device.device_type if cgm_device else None,
        baseline_sleep_hrs=float(lifestyle.baseline_sleep_hrs) if lifestyle and lifestyle.baseline_sleep_hrs else None,
        baseline_activity_level=lifestyle.baseline_activity_level if lifestyle else None,
        baseline_stress_level=lifestyle.baseline_stress_level if lifestyle else None,
        baseline_calories=lifestyle.baseline_calories if lifestyle else None
    )

@router.post("/inference/bolus")
async def recommend_bolus(request: BolusRequest, db: AsyncSession = Depends(get_db)):
    
    # 1. Get user context (ICR, ISF, targets etc.)
    context = await get_user_context(request.user_id, db)
    
    # 2. Build feature vector
    features = build_feature_vector(request, context)
    
    # 3. Run inference engine
    recommendation = inference_engine.predict(features, context)
    
    # 4. Audit log every recommendation
    await log_recommendation(db, request.user_id, features, recommendation)
    
    return recommendation
