"""Tests for get_current_device (app/core/device_auth.py), mirroring the
get_current_user test surface: revoked/stale-tv/unknown-device rejection,
and — the explicit cross-audience requirement — that a *user* access token
is never accepted here, symmetric to get_current_user rejecting a device
token (covered in test_cross_audience_isolation.py).
"""

from __future__ import annotations

import uuid

import pytest
from fastapi import HTTPException

from app.core.device_auth import get_current_device
from app.core.security import create_access_token, create_device_access_token
from app.models.device import Device

from .conftest import build_sqlite_db, make_user


async def _make_device(session_factory, **kwargs):
    device = Device(id=uuid.uuid4(), hardware_id=kwargs.pop("hardware_id", "pi-1"), **kwargs)
    async with session_factory() as session:
        session.add(device)
        await session.commit()
        await session.refresh(device)
    return device


async def test_valid_device_token_resolves_device_and_user():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    device = await _make_device(session_factory, user_id=user.id, token_version=0)
    token = create_device_access_token(device.id, user.id, token_version=0)

    async with session_factory() as session:
        resolved_device, user_id = await get_current_device(
            authorization=f"Bearer {token}", db=session
        )

    assert resolved_device.id == device.id
    assert user_id == str(user.id)
    await engine.dispose()


async def test_missing_authorization_header_rejected():
    engine, session_factory = await build_sqlite_db()
    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_device(authorization=None, db=session)
    assert exc_info.value.status_code == 401
    await engine.dispose()


async def test_unknown_device_rejected():
    engine, session_factory = await build_sqlite_db()
    token = create_device_access_token(uuid.uuid4(), uuid.uuid4(), token_version=0)
    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_device(authorization=f"Bearer {token}", db=session)
    assert exc_info.value.status_code == 404
    await engine.dispose()


async def test_revoked_device_rejected():
    from datetime import datetime, timezone

    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    device = await _make_device(
        session_factory, user_id=user.id, token_version=0, revoked_at=datetime.now(timezone.utc)
    )
    token = create_device_access_token(device.id, user.id, token_version=0)

    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_device(authorization=f"Bearer {token}", db=session)
    assert exc_info.value.status_code == 401
    await engine.dispose()


async def test_stale_token_version_rejected():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    device = await _make_device(session_factory, user_id=user.id, token_version=1)
    # Minted before the device's token_version was bumped (unpair, or the
    # owning user's logout-all).
    stale_token = create_device_access_token(device.id, user.id, token_version=0)

    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_device(authorization=f"Bearer {stale_token}", db=session)
    assert exc_info.value.status_code == 401
    await engine.dispose()


async def test_user_access_token_is_rejected():
    """A user's own login token must never authenticate as a device."""
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    user_token = create_access_token(str(user.id), token_version=user.token_version)

    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_device(authorization=f"Bearer {user_token}", db=session)
    assert exc_info.value.status_code == 401
    await engine.dispose()


async def test_device_refresh_token_is_rejected_on_access_dependency():
    """A refresh token must not work where an access token is required."""
    from app.core.security import create_device_refresh_token

    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    device = await _make_device(session_factory, user_id=user.id, token_version=0)
    refresh_token = create_device_refresh_token(device.id, user.id, token_version=0)

    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_device(authorization=f"Bearer {refresh_token}", db=session)
    assert exc_info.value.status_code == 401
    await engine.dispose()
