from fastapi import APIRouter, Depends, HTTPException, status, Request, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, delete, update
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timedelta
import logging
import time
from collections import defaultdict

from ..database import get_db
from ..models.user import User, LoginAttempt
from ..models.device import Device
from ..core.security import (
    verify_password,
    get_password_hash,
    create_access_token,
    create_refresh_token,
    create_reset_token,
    create_verify_token,
    decode_token,
    decode_token_payload,
    TOKEN_TYPE_ACCESS,
    TOKEN_TYPE_REFRESH,
    TOKEN_TYPE_RESET,
    TOKEN_TYPE_VERIFY,
)
from ..core.password_policy import validate_password
from ..core.validators import normalize_email
from ..services.email_service import (
    send_password_reset_email,
    send_verification_email,
    send_account_locked_email,
)
from ..schemas.user import LoginResponse, UserProfileResponse

router = APIRouter()
logger = logging.getLogger("mytr.auth")

# ── Account lockout (persistent, per-email) ───────────────────────────────────
MAX_FAILED_ATTEMPTS = 5
LOCKOUT_WINDOW = timedelta(minutes=15)


async def _recent_failed_count(db: AsyncSession, email: str) -> int:
    since = datetime.utcnow() - LOCKOUT_WINDOW
    result = await db.execute(
        select(func.count())
        .select_from(LoginAttempt)
        .where(
            LoginAttempt.email == email,
            LoginAttempt.successful.is_(False),
            LoginAttempt.created_at >= since,
        )
    )
    return result.scalar() or 0


async def _record_login_attempt(db: AsyncSession, email: str, ip, successful: bool) -> None:
    db.add(LoginAttempt(email=email, ip=ip, successful=successful, created_at=datetime.utcnow()))
    await db.commit()


async def _clear_failed_attempts(db: AsyncSession, email: str) -> None:
    await db.execute(
        delete(LoginAttempt).where(
            LoginAttempt.email == email,
            LoginAttempt.successful.is_(False),
        )
    )
    await db.commit()

# ── Rate limiting ─────────────────────────────────────────────────────────────
# Per-IP sliding-window limiter. Each bucket name has its own history so login
# brute-force attempts don't share a budget with e.g. email existence checks.
_rate_buckets: dict = defaultdict(list)


def _check_rate_limit(request: Request, bucket: str, limit: int, window: int = 60):
    ip = request.client.host if request.client else "unknown"
    key = f"{bucket}:{ip}"
    now = time.time()
    _rate_buckets[key] = [t for t in _rate_buckets[key] if now - t < window]
    if len(_rate_buckets[key]) >= limit:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests. Please try again later.",
        )
    _rate_buckets[key].append(now)


# ── Reusable auth dependency ──────────────────────────────────────────────────
async def get_current_user(
    authorization: str = Header(None),
    db: AsyncSession = Depends(get_db),
) -> User:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Not authenticated")
    token = authorization.replace("Bearer ", "")
    payload = decode_token_payload(token, expected_type=TOKEN_TYPE_ACCESS)
    if payload is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    result = await db.execute(select(User).where(User.id == payload.get("sub")))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    # Reject tokens issued before the last "log out everywhere" / password change.
    if payload.get("tv", 0) != (user.token_version or 0):
        raise HTTPException(status_code=401, detail="Session expired. Please sign in again.")
    return user


async def get_verified_user(current_user: User = Depends(get_current_user)) -> User:
    """Like get_current_user, but also requires a confirmed email address.
    Use this dependency to gate features that should be unavailable until the
    user verifies their email (returns 403 with a machine-readable code)."""
    if not current_user.email_verified:
        raise HTTPException(
            status_code=403,
            detail={"code": "EMAIL_NOT_VERIFIED", "message": "Please verify your email to use this feature."},
        )
    return current_user


# ── Schemas ───────────────────────────────────────────────────────────────────
class LoginRequest(BaseModel):
    email: str
    password: str
    device_id: Optional[str] = None
    device_name: Optional[str] = None
    remember_me: bool = False


class RefreshRequest(BaseModel):
    refresh_token: str


class ForgotPasswordRequest(BaseModel):
    email: str


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.post("/refresh", response_model=LoginResponse)
async def refresh_token(request: RefreshRequest, http_request: Request, db: AsyncSession = Depends(get_db)):
    payload = decode_token_payload(request.refresh_token, expected_type=TOKEN_TYPE_REFRESH)
    if payload is None:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    result = await db.execute(select(User).where(User.id == payload.get("sub")))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    if payload.get("tv", 0) != (user.token_version or 0):
        raise HTTPException(status_code=401, detail="Session expired. Please sign in again.")

    tv = user.token_version or 0
    access_token = create_access_token(str(user.id), token_version=tv)
    new_refresh_token = create_refresh_token(str(user.id), token_version=tv)
    user_type = user.diabetes_type.lower() if user.diabetes_type else "fitness"

    # A real production bug this fixes: libre_account_registry.py's
    # get_eligible_accounts uses "a successful LoginAttempt in the last 7
    # days" as its proxy for "this user is actively using the app," to
    # bound the shared Libre poller to accounts someone might actually be
    # looking at. But a mobile app normally stays "logged in" indefinitely
    # via exactly this silent refresh flow, never re-touching /login after
    # the first time — so that proxy was structurally wrong for the normal
    # case, not just this one account: any user who logged in with a
    # password more than 7 days ago and has been silently refreshing ever
    # since would never register as having a "recent session" again, no
    # matter how many times they reconnect a CGM device, and the shared
    # poller would never pick them up. A successful refresh proves an
    # active session exactly as well as a fresh login does for this
    # purpose, so it now records the same way.
    ip = http_request.client.host if http_request.client else None
    await _record_login_attempt(db, user.email, ip, successful=True)

    return LoginResponse(
        access_token=access_token,
        refresh_token=new_refresh_token,
        user_id=str(user.id),
        user_type=user_type,
        name=user.name,
    )


@router.post("/login", response_model=LoginResponse)
async def login(request: LoginRequest, http_request: Request, db: AsyncSession = Depends(get_db)):
    # First line: per-IP burst throttle. Second line: persistent per-account
    # lockout in Postgres (survives restarts, shared across instances).
    _check_rate_limit(http_request, bucket="login", limit=10, window=60)

    email = normalize_email(request.email)
    ip = http_request.client.host if http_request.client else None

    if await _recent_failed_count(db, email) >= MAX_FAILED_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_423_LOCKED,
            detail="Account temporarily locked after too many failed attempts. "
                   "Try again in 15 minutes, or reset your password to unlock it now.",
        )

    result = await db.execute(select(User).where(func.lower(User.email) == email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(request.password, user.password_hash):
        await _record_login_attempt(db, email, ip, successful=False)
        # If this failure just tripped the threshold, notify the real owner.
        if await _recent_failed_count(db, email) == MAX_FAILED_ATTEMPTS and user is not None:
            try:
                await send_account_locked_email(user.email)
            except Exception:
                logger.exception("Failed to send lockout email to %s", user.email)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    # Successful login clears the failure counter (unlocks the account).
    await _clear_failed_attempts(db, email)

    tv = user.token_version or 0
    access_token = create_access_token(str(user.id), token_version=tv)
    refresh_token = create_refresh_token(
        str(user.id), token_version=tv, remember_me=request.remember_me
    )
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
        email_verified=current_user.email_verified,
    )


@router.get("/check-email")
async def check_email(email: str, request: Request, db: AsyncSession = Depends(get_db)):
    _check_rate_limit(request, bucket="check_email", limit=10, window=60)
    normalised = email.strip().lower()
    result = await db.execute(select(User).where(func.lower(User.email) == normalised))
    existing_user = result.scalar_one_or_none()
    return {"exists": existing_user is not None}


@router.post("/forgot-password")
async def forgot_password(
    request: ForgotPasswordRequest,
    http_request: Request,
    db: AsyncSession = Depends(get_db),
):
    _check_rate_limit(http_request, bucket="forgot_password", limit=5, window=60)

    email = request.email.strip().lower()
    result = await db.execute(select(User).where(func.lower(User.email) == email))
    user = result.scalar_one_or_none()

    # Only send a link if the account exists, but always return the same
    # response so the endpoint can't be used to enumerate registered emails.
    if user:
        reset_token = create_reset_token(str(user.id))
        await send_password_reset_email(email=user.email, reset_token=reset_token)

    return {
        "message": "If an account exists for this email, a password reset link has been sent."
    }


@router.post("/reset-password")
async def reset_password(
    request: ResetPasswordRequest,
    http_request: Request,
    db: AsyncSession = Depends(get_db),
):
    _check_rate_limit(http_request, bucket="reset_password", limit=5, window=60)

    user_id = decode_token(request.token, expected_type=TOKEN_TYPE_RESET)
    if user_id is None:
        raise HTTPException(status_code=400, detail="Invalid or expired reset link.")

    password_error = validate_password(request.new_password)
    if password_error:
        raise HTTPException(status_code=400, detail=password_error)

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=400, detail="Invalid or expired reset link.")

    user.password_hash = get_password_hash(request.new_password)
    await db.commit()

    # Resetting the password also clears any lockout on the account.
    await _clear_failed_attempts(db, normalize_email(user.email))

    return {"message": "Password has been reset. You can now sign in."}


@router.post("/send-verification-email")
async def send_verification(
    http_request: Request,
    current_user: User = Depends(get_current_user),
):
    _check_rate_limit(http_request, bucket="send_verification", limit=5, window=60)

    if current_user.email_verified:
        return {"message": "Email already verified."}

    token = create_verify_token(str(current_user.id))
    await send_verification_email(email=current_user.email, verify_token=token)
    return {"message": "Verification email sent."}


@router.post("/verify-email")
async def verify_email(token: str, db: AsyncSession = Depends(get_db)):
    user_id = decode_token(token, expected_type=TOKEN_TYPE_VERIFY)
    if user_id is None:
        raise HTTPException(status_code=400, detail="Invalid or expired verification link.")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=400, detail="Invalid or expired verification link.")

    if not user.email_verified:
        user.email_verified = True
        await db.commit()

    return {"message": "Email verified. Thank you!"}


@router.post("/logout-all")
async def logout_all_devices(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Revoke every access/refresh token issued for this account on all
    sessions AND every paired desk device (architecture-v3.md §2.1).
    The caller's own token is invalidated too, so the client must sign in
    again."""
    current_user.token_version = (current_user.token_version or 0) + 1
    await db.execute(
        update(Device)
        .where(Device.user_id == current_user.id, Device.revoked_at.is_(None))
        .values(token_version=Device.token_version + 1)
    )
    await db.commit()
    return {"message": "Signed out of all devices."}
