"""Tests that logout-all revokes paired devices too (architecture-v3.md
§2.1: "the user's global logout-all ... bumps every owned device's
token_version"), not just the user's own session tokens.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.api.auth import logout_all_devices
from app.core.device_auth import get_current_device
from app.core.security import create_device_access_token
from app.models.device import Device
from app.models.user import User

from .conftest import build_sqlite_db, make_user


async def test_logout_all_bumps_active_owned_devices():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")

    device = Device(id=uuid.uuid4(), hardware_id="pi-1", user_id=user.id, token_version=0)
    async with session_factory() as session:
        session.add(device)
        await session.commit()

    old_device_token = create_device_access_token(device.id, user.id, token_version=0)

    # Sanity: the token works before logout-all.
    async with session_factory() as session:
        resolved_device, _ = await get_current_device(
            authorization=f"Bearer {old_device_token}", db=session
        )
        assert resolved_device.id == device.id

    async with session_factory() as session:
        result = await session.execute(select(User).where(User.id == user.id))
        session_user = result.scalar_one()
        await logout_all_devices(db=session, current_user=session_user)

    # The user's own token_version moved on.
    async with session_factory() as session:
        result = await session.execute(select(User).where(User.id == user.id))
        assert result.scalar_one().token_version == 1

    # The device's pre-logout-all token is now rejected.
    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_device(authorization=f"Bearer {old_device_token}", db=session)
    assert exc_info.value.status_code == 401

    await engine.dispose()


async def test_logout_all_does_not_touch_already_revoked_devices():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")

    revoked_device = Device(
        id=uuid.uuid4(),
        hardware_id="pi-2",
        user_id=user.id,
        token_version=0,
        revoked_at=datetime.now(timezone.utc),
    )
    async with session_factory() as session:
        session.add(revoked_device)
        await session.commit()

    async with session_factory() as session:
        result = await session.execute(select(User).where(User.id == user.id))
        session_user = result.scalar_one()
        await logout_all_devices(db=session, current_user=session_user)

    async with session_factory() as session:
        result = await session.execute(select(Device).where(Device.id == revoked_device.id))
        assert result.scalar_one().token_version == 0

    await engine.dispose()


async def test_logout_all_does_not_touch_other_users_devices():
    engine, session_factory = await build_sqlite_db()
    user_a = await make_user(session_factory, "a@example.com")
    user_b = await make_user(session_factory, "b@example.com")

    device_b = Device(id=uuid.uuid4(), hardware_id="pi-3", user_id=user_b.id, token_version=0)
    async with session_factory() as session:
        session.add(device_b)
        await session.commit()

    async with session_factory() as session:
        result = await session.execute(select(User).where(User.id == user_a.id))
        session_user_a = result.scalar_one()
        await logout_all_devices(db=session, current_user=session_user_a)

    async with session_factory() as session:
        result = await session.execute(select(Device).where(Device.id == device_b.id))
        assert result.scalar_one().token_version == 0

    await engine.dispose()
