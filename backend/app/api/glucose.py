from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.user import User
from ..services.glucose.manual_log_service import log_manual_glucose_reading
from .auth import get_current_user

router = APIRouter()


class ManualGlucoseRequest(BaseModel):
    value_mgdl: int
    timestamp: datetime


@router.post("/glucose/manual")
async def log_manual_glucose(
    request: ManualGlucoseRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        reading_id = await log_manual_glucose_reading(
            current_user.id, request.value_mgdl, request.timestamp,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    return {"success": True, "reading_id": reading_id}
