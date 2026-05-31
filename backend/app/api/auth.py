from fastapi import APIRouter, Depends, HTTPException, status, Request, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from jose import jwt, JWTError
from pydantic import BaseModel
from typing import Optional
import time
from collections import defaultdict

from ..database import get_db
from ..models.user import User
from ..core.security import (
    verify_password,
    create_access_token,
    create_refresh_token,
    SECRET_KEY,
    ALGORITHM,
)
from ..schemas.user import LoginResponse, UserProfileResponse

router = APIRouter()

# ── Rate limiting ─────────────────────────────────────────────────────────────
_check_email_rates: dict = defaultdict(list)
RATE_LIMIT = 10
RATE_WINDOW = 60  # seconds


def _check_rate_limit(request: Request):
    ip = request.client.host
    now = time.time()
    _check_email_rates[ip] = [t for t in _check_email_rates[ip] if now - t < RATE_WINDOW]
    if len(_check_email_rates[ip]) >= RATE_LIMIT:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many requests")
    _check_email_rates[ip].append(now)


# ── Reusable auth dependency ──────────────────────────────────────────────────
async def get_current_user(
    authorization: str = Header(None),
    db: AsyncSession = Depends(get_db),
) -> User:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Not authenticated")
    token = authorization.replace("Bearer ", "")
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid token")
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


# ── Schemas ───────────────────────────────────────────────────────────────────
class LoginRequest(BaseModel):
    email: str
    password: str
    device_id: Optional[str] = None
    device_name: Optional[str] = None


class RefreshRequest(BaseModel):
    refresh_token: str


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.post("/refresh", response_model=LoginResponse)
async def refresh_token(request: RefreshRequest, db: AsyncSession = Depends(get_db)):
    try:
        payload = jwt.decode(request.refresh_token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid refresh token")
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")

    access_token = create_access_token(str(user.id))
    new_refresh_token = create_refresh_token(str(user.id))
    user_type = user.diabetes_type.lower() if user.diabetes_type else "fitness"

    return LoginResponse(
        access_token=access_token,
        refresh_token=new_refresh_token,
        user_id=str(user.id),
        user_type=user_type,
        name=user.name,
    )


@router.post("/login", response_model=LoginResponse)
async def login(request: LoginRequest, db: AsyncSession = Depends(get_db)):
    email = request.email.strip().lower()
    result = await db.execute(select(User).where(func.lower(User.email) == email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(request.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    access_token = create_access_token(str(user.id))
    refresh_token = create_refresh_token(str(user.id))
    user_type = user.diabetes_type.lower() if user.diabetes_type else "fitness"

    return LoginResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=str(user.id),
        user_type=user_type,
        name=user.name,
    )


@router.get("/me", response_model=UserProfileResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    user_type = current_user.diabetes_type.lower() if current_user.diabetes_type else "fitness"
    onboarding_complete = current_user.consent_confirmed_at is not None

    return UserProfileResponse(
        id=str(current_user.id),
        name=current_user.name,
        email=current_user.email,
        user_type=user_type,
        diabetes_type=current_user.diabetes_type,
        onboarding_complete=onboarding_complete,
    )


@router.get("/check-email")
async def check_email(email: str, request: Request, db: AsyncSession = Depends(get_db)):
    _check_rate_limit(request)
    normalised = email.strip().lower()
    result = await db.execute(select(User).where(func.lower(User.email) == normalised))
    existing_user = result.scalar_one_or_none()
    return {"exists": existing_user is not None}
