from datetime import date
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.activity import ActivityLog
from .auth import get_current_user
from ..models.user import User

router = APIRouter()


class ActivitySyncRequest(BaseModel):
    steps_today: int = 0
    calories_burned: int = 0
    heart_rate: int = 0


@router.post("/activity/sync")
async def sync_activity(
    body: ActivitySyncRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    today = date.today()

    # UPSERT — one row per user per day, last write wins
    await db.execute(
        text("""
            INSERT INTO activity_logs (user_id, date, steps_today, calories_burned, heart_rate, synced_at)
            VALUES (:user_id, :date, :steps, :calories, :hr, now())
            ON CONFLICT (user_id, date)
            DO UPDATE SET
                steps_today     = EXCLUDED.steps_today,
                calories_burned = EXCLUDED.calories_burned,
                heart_rate      = EXCLUDED.heart_rate,
                synced_at       = now()
        """),
        {
            "user_id": current_user.id,
            "date": today,
            "steps": body.steps_today,
            "calories": body.calories_burned,
            "hr": body.heart_rate,
        },
    )
    await db.commit()
    return {"status": "ok"}
