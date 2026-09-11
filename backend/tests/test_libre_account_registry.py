"""Tests for the shared poller's account registry (architecture-v3.md §3.2):
who gets polled, and how accounts sharing one Libre login group together.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta

from app.core.encryption import encrypt
from app.core.secrets_manager import secrets_manager
from app.models.device import Device
from app.models.user import CGMDevice, LoginAttempt
from app.services.cgm.libre_account_registry import get_eligible_accounts, group_by_credential

from .conftest import build_sqlite_db, make_user


async def _add_cgm_device(session_factory, user_id, device_type="LIBRE_3", is_active=True, deleted_at=None):
    async with session_factory() as session:
        device = CGMDevice(
            user_id=user_id, device_type=device_type, is_active=is_active, deleted_at=deleted_at,
        )
        session.add(device)
        await session.commit()
        await session.refresh(device)
    return device


async def _add_desk_device(session_factory, user_id, revoked_at=None):
    async with session_factory() as session:
        device = Device(
            id=uuid.uuid4(), hardware_id=f"pi-{uuid.uuid4()}", user_id=user_id, revoked_at=revoked_at,
        )
        session.add(device)
        await session.commit()


async def _add_login_attempt(session_factory, email, when, successful=True):
    async with session_factory() as session:
        session.add(LoginAttempt(email=email, ip="1.2.3.4", successful=successful, created_at=when))
        await session.commit()


async def _store_libre_creds(user_id, email="libre@example.com", password="pw"):
    await secrets_manager.store_libre_credentials(str(user_id), email, encrypt(password))


async def test_user_without_credentials_is_excluded():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _add_cgm_device(session_factory, user.id)
    await _add_desk_device(session_factory, user.id)

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    assert not any(a.user_id == user.id for a in accounts)
    await engine.dispose()


async def test_user_without_active_cgm_connection_is_excluded():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _store_libre_creds(user.id)
    await _add_desk_device(session_factory, user.id)
    # No CGMDevice row at all.

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    assert not any(a.user_id == user.id for a in accounts)
    await engine.dispose()


async def test_manual_cgm_connection_does_not_count_as_libre():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _store_libre_creds(user.id)
    await _add_cgm_device(session_factory, user.id, device_type="MANUAL")
    await _add_desk_device(session_factory, user.id)

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    assert not any(a.user_id == user.id for a in accounts)
    await engine.dispose()


async def test_deleted_cgm_connection_is_excluded():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _store_libre_creds(user.id)
    await _add_cgm_device(session_factory, user.id, deleted_at=datetime.utcnow())
    await _add_desk_device(session_factory, user.id)

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    assert not any(a.user_id == user.id for a in accounts)
    await engine.dispose()


async def test_active_device_alone_is_sufficient():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _store_libre_creds(user.id, email="withdevice@example.com")
    await _add_cgm_device(session_factory, user.id)
    await _add_desk_device(session_factory, user.id)
    # No login attempts at all.

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    matches = [a for a in accounts if a.user_id == user.id]
    assert len(matches) == 1
    assert matches[0].email == "withdevice@example.com"
    await engine.dispose()


async def test_recent_login_alone_is_sufficient_without_a_device():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _store_libre_creds(user.id)
    await _add_cgm_device(session_factory, user.id)
    await _add_login_attempt(session_factory, user.email, datetime.utcnow() - timedelta(days=1))
    # No desk device at all.

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    assert any(a.user_id == user.id for a in accounts)
    await engine.dispose()


# ── Timezone resolution ──────────────────────────────────────────────────────
#
# Regression coverage for a real production bug: users.timezone has
# server_default='UTC' and nothing anywhere in the app ever sets it to a real
# IANA zone, so it was always the literal string "UTC" for every account —
# never the operator-configured LIBRE_ACCOUNT_TIMEZONE the on-demand
# connect-time fetch already respects. Treating an account's real local
# Libre timestamps as already-UTC shifts every stored reading forward by the
# account's real UTC offset (confirmed directly: a reading's recorded_at came
# out in the future relative to the database's own clock, for a real
# India-based account).

async def test_timezone_falls_back_to_the_global_setting_when_user_timezone_is_the_unset_default(monkeypatch):
    from app.services.cgm import libre_account_registry as registry_mod

    monkeypatch.setattr(registry_mod.settings, "LIBRE_ACCOUNT_TIMEZONE", "Asia/Kolkata")

    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")  # timezone left at its DB default: "UTC"
    await _store_libre_creds(user.id)
    await _add_cgm_device(session_factory, user.id)
    await _add_desk_device(session_factory, user.id)

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)

    match = next(a for a in accounts if a.user_id == user.id)
    assert match.timezone == "Asia/Kolkata"
    await engine.dispose()


async def test_timezone_respects_a_real_per_user_value_once_actually_set(monkeypatch):
    from sqlalchemy import update
    from app.models.user import User
    from app.services.cgm import libre_account_registry as registry_mod

    monkeypatch.setattr(registry_mod.settings, "LIBRE_ACCOUNT_TIMEZONE", "")  # nothing globally configured

    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    async with session_factory() as db:
        await db.execute(update(User).where(User.id == user.id).values(timezone="Europe/London"))
        await db.commit()
    await _store_libre_creds(user.id)
    await _add_cgm_device(session_factory, user.id)
    await _add_desk_device(session_factory, user.id)

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)

    match = next(a for a in accounts if a.user_id == user.id)
    assert match.timezone == "Europe/London"
    await engine.dispose()


async def test_no_device_and_no_recent_session_is_excluded():
    """The bound: an account connected once, never opened since, and no
    desk device — must not generate unbounded Abbott traffic forever."""
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _store_libre_creds(user.id)
    await _add_cgm_device(session_factory, user.id)
    # No device, no login attempts at all.

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    assert not any(a.user_id == user.id for a in accounts)
    await engine.dispose()


async def test_login_older_than_7_days_does_not_count_without_a_device():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _store_libre_creds(user.id)
    await _add_cgm_device(session_factory, user.id)
    await _add_login_attempt(session_factory, user.email, datetime.utcnow() - timedelta(days=8))

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    assert not any(a.user_id == user.id for a in accounts)
    await engine.dispose()


async def test_revoked_device_does_not_count_as_active():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _store_libre_creds(user.id)
    await _add_cgm_device(session_factory, user.id)
    await _add_desk_device(session_factory, user.id, revoked_at=datetime.utcnow())
    # No recent login either.

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    assert not any(a.user_id == user.id for a in accounts)
    await engine.dispose()


async def test_failed_login_does_not_count_as_a_session():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _store_libre_creds(user.id)
    await _add_cgm_device(session_factory, user.id)
    await _add_login_attempt(
        session_factory, user.email, datetime.utcnow() - timedelta(days=1), successful=False
    )

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)
    assert not any(a.user_id == user.id for a in accounts)
    await engine.dispose()


async def test_group_by_credential_dedupes_shared_libre_login():
    engine, session_factory = await build_sqlite_db()
    user_a = await make_user(session_factory, "a@example.com")
    user_b = await make_user(session_factory, "b@example.com")
    shared_email = f"shared-{uuid.uuid4()}@example.com"
    await _store_libre_creds(user_a.id, email=shared_email)
    await _store_libre_creds(user_b.id, email=shared_email)
    await _add_cgm_device(session_factory, user_a.id)
    await _add_cgm_device(session_factory, user_b.id)
    await _add_desk_device(session_factory, user_a.id)
    await _add_desk_device(session_factory, user_b.id)

    async with session_factory() as db:
        accounts = await get_eligible_accounts(db)

    relevant = [a for a in accounts if a.email.lower() == shared_email.lower()]
    assert len(relevant) == 2

    groups = group_by_credential(accounts)
    assert len(groups[shared_email.lower()]) == 2
    user_ids_in_group = {a.user_id for a in groups[shared_email.lower()]}
    assert user_ids_in_group == {user_a.id, user_b.id}
    await engine.dispose()
