import os
from datetime import datetime, timedelta
from typing import Any, Optional, Union

import bcrypt
from jose import jwt, JWTError

SECRET_KEY = os.getenv("JWT_SECRET")
if not SECRET_KEY:
    raise RuntimeError("JWT_SECRET environment variable is not set")

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24            # 1 day
REFRESH_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7       # 7 days (standard session)
REFRESH_TOKEN_REMEMBER_MINUTES = 60 * 24 * 30    # 30 days ("remember me")
RESET_TOKEN_EXPIRE_MINUTES = 30                  # password-reset link validity
VERIFY_TOKEN_EXPIRE_MINUTES = 60 * 24            # email-verification link validity
DEVICE_ACCESS_TOKEN_EXPIRE_MINUTES = 60          # 1 hour
DEVICE_REFRESH_TOKEN_EXPIRE_MINUTES = 60 * 24 * 90  # 90 days, rotated on use

# Token "type" claim values — prevent a token of one kind being used as another
# (e.g. presenting a refresh token to an access-protected route, or vice versa).
TOKEN_TYPE_ACCESS = "access"
TOKEN_TYPE_REFRESH = "refresh"
TOKEN_TYPE_RESET = "reset"
TOKEN_TYPE_VERIFY = "verify"
# Device tokens are a separate audience from user tokens (architecture-v3.md
# §2.1): distinct `type` values so a stolen device token can never decode as
# a user access token (full app API) or vice versa. Never reuse the user
# TOKEN_TYPE_* constants for device tokens.
TOKEN_TYPE_DEVICE_ACCESS = "device_access"
TOKEN_TYPE_DEVICE_REFRESH = "device_refresh"


def _create_token(
    subject: Union[str, Any],
    token_type: str,
    expires_delta: timedelta,
    token_version: Optional[int] = None,
) -> str:
    expire = datetime.utcnow() + expires_delta
    claims = {"exp": expire, "sub": str(subject), "type": token_type}
    # Session tokens (access/refresh) carry the user's token_version so a bump
    # on the user record revokes them. Stateless reset/verify tokens omit it.
    if token_version is not None:
        claims["tv"] = token_version
    return jwt.encode(claims, SECRET_KEY, algorithm=ALGORITHM)


def create_access_token(
    subject: Union[str, Any],
    expires_delta: timedelta = None,
    token_version: int = 0,
) -> str:
    return _create_token(
        subject, TOKEN_TYPE_ACCESS,
        expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
        token_version=token_version,
    )


def create_refresh_token(
    subject: Union[str, Any],
    expires_delta: timedelta = None,
    token_version: int = 0,
    remember_me: bool = False,
) -> str:
    if expires_delta is None:
        minutes = REFRESH_TOKEN_REMEMBER_MINUTES if remember_me else REFRESH_TOKEN_EXPIRE_MINUTES
        expires_delta = timedelta(minutes=minutes)
    return _create_token(
        subject, TOKEN_TYPE_REFRESH, expires_delta,
        token_version=token_version,
    )


def create_reset_token(subject: Union[str, Any], expires_delta: timedelta = None) -> str:
    return _create_token(
        subject, TOKEN_TYPE_RESET,
        expires_delta or timedelta(minutes=RESET_TOKEN_EXPIRE_MINUTES),
    )


def create_verify_token(subject: Union[str, Any], expires_delta: timedelta = None) -> str:
    return _create_token(
        subject, TOKEN_TYPE_VERIFY,
        expires_delta or timedelta(minutes=VERIFY_TOKEN_EXPIRE_MINUTES),
    )


def _create_device_token(
    device_id: Union[str, Any],
    user_id: Union[str, Any],
    token_type: str,
    expires_delta: timedelta,
    token_version: int,
) -> str:
    # sub = device_id (mirrors user tokens, where sub = user_id), uid = the
    # owning user so device-scoped code can identify the user without a
    # second lookup, tv = devices.token_version (not users.token_version —
    # unpairing a device must not affect the user's own sessions).
    expire = datetime.utcnow() + expires_delta
    claims = {
        "exp": expire,
        "sub": str(device_id),
        "type": token_type,
        "uid": str(user_id),
        "tv": token_version,
    }
    return jwt.encode(claims, SECRET_KEY, algorithm=ALGORITHM)


def create_device_access_token(
    device_id: Union[str, Any],
    user_id: Union[str, Any],
    token_version: int = 0,
    expires_delta: timedelta = None,
) -> str:
    return _create_device_token(
        device_id, user_id, TOKEN_TYPE_DEVICE_ACCESS,
        expires_delta or timedelta(minutes=DEVICE_ACCESS_TOKEN_EXPIRE_MINUTES),
        token_version=token_version,
    )


def create_device_refresh_token(
    device_id: Union[str, Any],
    user_id: Union[str, Any],
    token_version: int = 0,
    expires_delta: timedelta = None,
) -> str:
    return _create_device_token(
        device_id, user_id, TOKEN_TYPE_DEVICE_REFRESH,
        expires_delta or timedelta(minutes=DEVICE_REFRESH_TOKEN_EXPIRE_MINUTES),
        token_version=token_version,
    )


def decode_token_payload(token: str, expected_type: str) -> Optional[dict]:
    """
    Decode a JWT and verify its `type` claim matches `expected_type`.
    Returns the full claims dict on success, or None if the token is invalid,
    expired, or of the wrong type. Callers that also need to enforce the
    `tv` (token_version) claim should use this and compare against the user.
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None
    if payload.get("type") != expected_type:
        return None
    return payload


def decode_token(token: str, expected_type: str) -> Optional[str]:
    """
    Decode a JWT and return the subject (user id), or None if invalid/expired/
    wrong type. Does not check token_version — use for stateless reset/verify
    tokens, or alongside decode_token_payload for session tokens.
    """
    payload = decode_token_payload(token, expected_type)
    return payload.get("sub") if payload else None


def get_password_hash(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(plain_password: str, hashed_password: str) -> bool:
    # bcrypt.checkpw raises ValueError on malformed/non-bcrypt hashes (e.g.
    # legacy sha256). Treat those as a failed match rather than a 500.
    try:
        return bcrypt.checkpw(plain_password.encode(), hashed_password.encode())
    except ValueError:
        return False
