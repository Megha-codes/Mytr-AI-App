"""Structural tests for migration 010: users.timezone, devices,
device_pairing_codes (architecture-v3.md §1.1 / §1.2)."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from app.models.device import Device, DevicePairingCode

from .conftest import build_sqlite_db, make_user


async def test_user_timezone_defaults_to_utc():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    assert user.timezone == "UTC"
    await engine.dispose()


async def test_device_defaults():
    engine, session_factory = await build_sqlite_db()
    device = Device(id=uuid.uuid4(), hardware_id="pi-serial-1", firmware_version="1.0.0")
    async with session_factory() as session:
        session.add(device)
        await session.commit()
        await session.refresh(device)

    assert device.user_id is None
    assert device.kind == "DESK"
    assert device.token_version == 0
    assert device.revoked_at is None
    assert device.created_at is not None
    await engine.dispose()


async def test_device_pairing_code_links_to_device():
    engine, session_factory = await build_sqlite_db()
    device = Device(id=uuid.uuid4(), hardware_id="pi-serial-2")
    async with session_factory() as session:
        session.add(device)
        await session.commit()
        await session.refresh(device)

        code = DevicePairingCode(
            code="ABCD1234",
            hardware_id="pi-serial-2",
            device_id=device.id,
            expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
        )
        session.add(code)
        await session.commit()
        await session.refresh(code)

    assert code.device_id == device.id
    assert code.claimed_by is None
    assert code.expires_at > datetime.now(timezone.utc)
    await engine.dispose()
