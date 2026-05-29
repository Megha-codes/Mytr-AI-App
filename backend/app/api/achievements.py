from fastapi import APIRouter, Depends

from ..models.user import User
from .auth import get_current_user

router = APIRouter()


@router.get("")
async def get_achievements(current_user: User = Depends(get_current_user)):
    is_diabetic = current_user.diabetes_type in ("T1", "T2")

    return [
        {
            "id": "first_meal",
            "title": "First Meal Logged",
            "icon": "utensils",
            "category": "nutrition",
            "is_unlocked": False,
        },
        {
            "id": "first_glucose",
            "title": "First Glucose Reading",
            "icon": "activity",
            "category": "diabetes" if is_diabetic else "wellness",
            "is_unlocked": False,
        },
        {
            "id": "profile_ready",
            "title": "Profile Ready",
            "icon": "user-check",
            "category": "wellness",
            "is_unlocked": True,
        },
    ]
