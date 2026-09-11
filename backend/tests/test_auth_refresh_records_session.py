"""Regression test for a real production bug: the shared Libre poller
(libre_account_registry.get_eligible_accounts) treats "a successful
LoginAttempt in the last 7 days" as its proxy for "this user is actively
using the app" — but /auth/refresh, the endpoint a mobile app actually
calls to silently stay logged in indefinitely, never recorded one at all.
Only /auth/login did. So any user who authenticated with a password more
than 7 days ago and has been silently refreshing ever since (completely
normal mobile app behavior — nobody re-types their password weekly) would
never register as having a "recent session" again, and the shared poller
would never pick up their CGM connection no matter how many times they
reconnected it or how long the app stayed running.

get_eligible_accounts itself needed no change — test_libre_account_registry.py
already proves it honors any successful LoginAttempt row regardless of
where it came from (test_recent_login_alone_is_sufficient_without_a_device).
The actual bug was that /auth/refresh never created one.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import select

from app.api.auth import LoginRequest, RefreshRequest, login, refresh_token
from app.core.encryption import encrypt
from app.core.secrets_manager import secrets_manager
from app.core.security import create_refresh_token, get_password_hash
from app.models.user import CGMDevice, LoginAttempt, User
from app.services.cgm.libre_account_registry import get_eligible_accounts

from .conftest import build_sqlite_db, make_user


class _FakeClient:
    def __init__(self, host):
        self.host = host


class _FakeRequest:
    """Minimal stand-in for fastapi.Request — refresh_token only reads
    http_request.client.host."""
    def __init__(self, host="1.2.3.4"):
        self.client = _FakeClient(host)


async def test_refresh_records_a_successful_login_attempt():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "refresher@example.com")
    token = create_refresh_token(str(user.id), token_version=user.token_version or 0)

    async with session_factory() as db:
        response = await refresh_token(RefreshRequest(refresh_token=token), _FakeRequest(), db)

    assert response.access_token
    assert response.refresh_token

    async with session_factory() as db:
        result = await db.execute(
            select(LoginAttempt).where(
                LoginAttempt.email == user.email,
                LoginAttempt.successful.is_(True),
            )
        )
        attempts = result.scalars().all()

    assert len(attempts) == 1, "refresh_token should record exactly one successful LoginAttempt"
    assert attempts[0].ip == "1.2.3.4"


async def test_refresh_only_session_still_counts_as_recent_for_the_libre_poller():
    """End-to-end proof of the actual bug: a user whose only "session
    activity" is a refresh (no fresh /login row at all) must still be
    picked up by get_eligible_accounts — this is what silently broke
    before /auth/refresh recorded anything."""
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "refresh-only@example.com")

    async with session_factory() as db:
        db.add(CGMDevice(
            user_id=user.id, device_type="LIBRE_3",
            is_active=True, connected_at=datetime.now(timezone.utc),
        ))
        await db.commit()

    await secrets_manager.store_libre_credentials(str(user.id), "libre@example.com", encrypt("pw"))

    # No /auth/login row at all for this user — only what refresh_token
    # itself records, via the real route function.
    token = create_refresh_token(str(user.id), token_version=user.token_version or 0)
    async with session_factory() as db:
        await refresh_token(RefreshRequest(refresh_token=token), _FakeRequest(), db)

    async with session_factory() as db:
        eligible = await get_eligible_accounts(db)

    assert any(a.user_id == user.id for a in eligible), (
        "a user with no desk device and no /auth/login, only a successful "
        "/auth/refresh, must still be eligible for the shared Libre poller"
    )


async def test_login_records_a_successful_login_attempt():
    """A second, bigger gap found while chasing this same bug: only
    /auth/login's FAILURE branch ever recorded a LoginAttempt row — the
    success path never did. has_recent_session requires successful=True,
    so it could never be satisfied by an actual login at all, correct
    password or not, independent of the /auth/refresh gap above."""
    engine, session_factory = await build_sqlite_db()

    password = "correct horse battery staple"
    async with session_factory() as db:
        user = User(
            id=uuid.uuid4(), email="loginuser@example.com",
            password_hash=get_password_hash(password),
            email_verified=True, created_at=datetime.now(timezone.utc),
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)

    async with session_factory() as db:
        response = await login(
            LoginRequest(email=user.email, password=password), _FakeRequest(), db,
        )

    assert response.access_token

    async with session_factory() as db:
        result = await db.execute(
            select(LoginAttempt).where(
                LoginAttempt.email == user.email.lower(),
                LoginAttempt.successful.is_(True),
            )
        )
        attempts = result.scalars().all()

    assert len(attempts) == 1, "login should record exactly one successful LoginAttempt"
