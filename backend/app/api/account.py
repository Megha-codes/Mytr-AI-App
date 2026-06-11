"""
Authenticated account-settings endpoints: change password, change email
(re-verification required), and delete account (GDPR / DPDPA erasure).

All routes require a valid access token (see `get_current_user`). Mutations that
change credentials bump the user's `token_version`, which transparently signs the
account out of every *other* device; the calling client is handed fresh tokens so
it stays signed in.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel

from ..database import get_db
from ..models.user import LoginAttempt, User
from ..core.security import (
    create_access_token,
    create_refresh_token,
    create_verify_token,
    get_password_hash,
    verify_password,
)
from ..core.password_policy import validate_password
from ..core.validators import is_valid_email, normalize_email
from ..services.email_service import send_verification_email
from ..schemas.user import LoginResponse
from .auth import get_current_user, _check_rate_limit

router = APIRouter()
logger = logging.getLogger("mytr.account")


# ── Schemas ───────────────────────────────────────────────────────────────────
class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


class ChangeEmailRequest(BaseModel):
    new_email: str
    password: str  # confirm identity before changing the login identifier


class DeleteAccountRequest(BaseModel):
    password: str  # confirm identity before irreversible deletion


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.post("/change-password", response_model=LoginResponse)
async def change_password(
    request: ChangePasswordRequest,
    http_request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _check_rate_limit(http_request, bucket="change_password", limit=5, window=60)

    if not verify_password(request.current_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect.")

    if verify_password(request.new_password, current_user.password_hash):
        raise HTTPException(
            status_code=400,
            detail="New password must be different from your current password.",
        )

    password_error = validate_password(request.new_password)
    if password_error:
        raise HTTPException(status_code=400, detail=password_error)

    current_user.password_hash = get_password_hash(request.new_password)
    # Revoke sessions on every other device; reissue for the caller below.
    current_user.token_version = (current_user.token_version or 0) + 1
    await db.commit()

    tv = current_user.token_version
    user_type = current_user.diabetes_type.lower() if current_user.diabetes_type else "fitness"
    return LoginResponse(
        access_token=create_access_token(str(current_user.id), token_version=tv),
        refresh_token=create_refresh_token(str(current_user.id), token_version=tv),
        user_id=str(current_user.id),
        user_type=user_type,
        name=current_user.name,
    )


@router.post("/change-email")
async def change_email(
    request: ChangeEmailRequest,
    http_request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _check_rate_limit(http_request, bucket="change_email", limit=5, window=60)

    if not verify_password(request.password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Password is incorrect.")

    if not is_valid_email(request.new_email):
        raise HTTPException(status_code=400, detail="Please enter a valid email address.")

    new_email = normalize_email(request.new_email)
    if new_email == normalize_email(current_user.email):
        raise HTTPException(status_code=400, detail="That is already your email address.")

    # Case-insensitive uniqueness check against all other accounts.
    result = await db.execute(
        select(User).where(func.lower(User.email) == new_email, User.id != current_user.id)
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="An account with this email already exists.")

    current_user.email = new_email
    # New address is unconfirmed until the verification link is followed.
    current_user.email_verified = False
    await db.commit()

    try:
        await send_verification_email(
            email=new_email,
            verify_token=create_verify_token(str(current_user.id)),
        )
    except Exception:
        logger.exception("Failed to send verification email to %s", new_email)

    return {"message": "Email updated. Check your inbox to verify the new address."}


@router.delete("", status_code=status.HTTP_200_OK)
async def delete_account(
    request: DeleteAccountRequest,
    http_request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Permanently delete the account and all data linked by foreign key.

    Child rows (insulin profiles, CGM/wearable devices, lifestyle baselines)
    are removed by ON DELETE CASCADE. login_attempts key off email, not a FK,
    so they're cleared explicitly."""
    _check_rate_limit(http_request, bucket="delete_account", limit=3, window=60)

    if not verify_password(request.password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Password is incorrect.")

    email = normalize_email(current_user.email)
    user_id = current_user.id

    await db.execute(delete(LoginAttempt).where(func.lower(LoginAttempt.email) == email))
    await db.execute(delete(User).where(User.id == user_id))
    await db.commit()

    logger.info("Account deleted: %s", user_id)
    return {"message": "Your account and associated data have been deleted."}
