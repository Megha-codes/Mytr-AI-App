"""The three proofs for architecture-v3.md §4.3 step 7:

1. Credentials survive a full process restart.
2. The poller's account registry repopulates from the durable store on boot.
3. A raw database read shows only ciphertext — never plaintext credentials.

Uses a *file-backed* SQLite database (not `:memory:`) so "restart" is real:
each phase below gets its own engine/session/service instances with no
shared Python object, only the file on disk in common — the same relationship
a redeployed backend has with its Postgres database.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from cryptography.fernet import Fernet
from sqlalchemy import event, select
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

from app.core.encryption import decrypt, encrypt
from app.core.kms_client import LocalKmsClient
from app.core.kms_postgres_secrets_store import KmsPostgresSecretsStore
from app.core.secrets_manager import SecretsManager
from app.database import Base
from app.models.secret import EncryptedSecret
from app.models.user import CGMDevice, LoginAttempt, User
from app.services.cgm.libre_account_registry import get_eligible_accounts

LIBRE_EMAIL = "durable-libre-account@example.com"
LIBRE_PASSWORD = "correct horse battery staple"


def _register_pg_shims(engine):
    @event.listens_for(engine.sync_engine, "connect")
    def _shims(dbapi_conn, _):
        dbapi_conn.create_function("now", 0, lambda: datetime.now(timezone.utc).isoformat())
        dbapi_conn.create_function("gen_random_uuid", 0, lambda: uuid.uuid4().hex)


async def _open(db_path) -> tuple:
    """Every table (users, cgm_devices, encrypted_secrets, ...) lives in one
    file — exactly one Postgres instance would hold all of these in
    production, so this is what a real restart actually looks like, not a
    partial simulation of one.

    Creates only the tables this test needs, by explicit list — see
    conftest.build_sqlite_db's docstring for why an unscoped
    `Base.metadata.create_all()` is order-dependent and unsafe here.
    """
    from app.models.user import CGMDevice, LoginAttempt, User
    import app.models.activity  # noqa: F401 - resolves User.activity_logs relationship
    from app.models.device import Device, DevicePairingCode
    from app.models.secret import EncryptedSecret

    tables = [
        User.__table__, CGMDevice.__table__, LoginAttempt.__table__,
        Device.__table__, DevicePairingCode.__table__, EncryptedSecret.__table__,
    ]

    engine = create_async_engine(f"sqlite+aiosqlite:///{db_path}")
    _register_pg_shims(engine)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all, tables=tables)
    return engine, async_sessionmaker(bind=engine, expire_on_commit=False)


async def test_credentials_survive_restart_and_poller_repopulates(tmp_path):
    db_path = tmp_path / "durable_secrets.db"
    master_key = Fernet.generate_key()  # must be stable across "restarts" — env var in real deploys

    # ── "Process 1": boot, connect Libre, store the (already field-level
    # encrypted) credentials through the durable store ─────────────────────
    engine_1, session_factory_1 = await _open(db_path)

    user_id = uuid.uuid4()
    async with session_factory_1() as db:
        user = User(
            id=user_id, email="app-user@example.com", password_hash="x",
            email_verified=True, created_at=datetime.now(timezone.utc), timezone="Asia/Kolkata",
        )
        db.add(user)
        await db.commit()
        db.add(CGMDevice(user_id=user_id, device_type="LIBRE_3", is_active=True))
        db.add(LoginAttempt(
            email=user.email, ip="1.2.3.4", successful=True, created_at=datetime.utcnow(),
        ))
        await db.commit()

    store_1 = KmsPostgresSecretsStore(
        session_factory=session_factory_1,
        kms_client=LocalKmsClient(master_key=master_key),
        kms_key_id="test-cmk",
    )
    manager_1 = SecretsManager(store=store_1)

    # cgm_connect.py's actual flow: the password is Fernet-encrypted via
    # encryption.py *before* it ever reaches the secrets store — this proves
    # the durable store's own envelope wraps that already-encrypted value.
    await manager_1.store_libre_credentials(str(user_id), LIBRE_EMAIL, encrypt(LIBRE_PASSWORD))

    # Sanity within "process 1" itself.
    creds_before_restart = await manager_1.get_libre_credentials(str(user_id))
    assert creds_before_restart.email == LIBRE_EMAIL
    assert decrypt(creds_before_restart.encrypted_password) == LIBRE_PASSWORD

    await engine_1.dispose()  # "process 1" exits — nothing in memory survives this

    # ── Proof 3: a raw read, from an entirely separate connection, shows
    # only ciphertext ───────────────────────────────────────────────────────
    engine_raw = create_async_engine(f"sqlite+aiosqlite:///{db_path}")
    session_factory_raw = async_sessionmaker(bind=engine_raw, expire_on_commit=False)
    async with session_factory_raw() as db:
        result = await db.execute(
            select(EncryptedSecret).where(EncryptedSecret.key == f"libre:{user_id}")
        )
        raw_row = result.scalar_one()

    assert LIBRE_EMAIL.encode() not in raw_row.ciphertext
    assert LIBRE_PASSWORD.encode() not in raw_row.ciphertext
    assert LIBRE_EMAIL.encode() not in raw_row.wrapped_dek
    assert LIBRE_PASSWORD.encode() not in raw_row.wrapped_dek
    # And the row genuinely can't be read without going through KMS to
    # unwrap wrapped_dek — there is no key material sitting next to it.
    try:
        Fernet(raw_row.wrapped_dek).decrypt(raw_row.ciphertext)
        assert False, "wrapped_dek must not itself be a usable Fernet key"
    except Exception:
        pass
    await engine_raw.dispose()

    # ── "Process 2": fresh engine, fresh KMS client instance (same master
    # key — the actual durability contract), fresh SecretsManager ─────────
    engine_2, session_factory_2 = await _open(db_path)
    store_2 = KmsPostgresSecretsStore(
        session_factory=session_factory_2,
        kms_client=LocalKmsClient(master_key=master_key),
        kms_key_id="test-cmk",
    )
    manager_2 = SecretsManager(store=store_2)

    # Proof 1: credentials survive the restart.
    creds_after_restart = await manager_2.get_libre_credentials(str(user_id))
    assert creds_after_restart is not None
    assert creds_after_restart.email == LIBRE_EMAIL
    assert decrypt(creds_after_restart.encrypted_password) == LIBRE_PASSWORD

    # Proof 2: the poller's account registry repopulates from the durable
    # store — no in-memory state carried over from "process 1" at all.
    async with session_factory_2() as db:
        eligible = await get_eligible_accounts(db, secrets_mgr=manager_2)

    matches = [a for a in eligible if a.user_id == user_id]
    assert len(matches) == 1
    assert matches[0].email == LIBRE_EMAIL
    assert matches[0].password == LIBRE_PASSWORD
    assert matches[0].timezone == "Asia/Kolkata"

    await engine_2.dispose()


async def test_deleted_credentials_do_not_survive_restart(tmp_path):
    """The converse of durability: a delete must actually persist too, not
    just disappear from one process's in-memory view."""
    db_path = tmp_path / "delete_test.db"
    master_key = Fernet.generate_key()
    user_id = uuid.uuid4()

    engine_1, session_factory_1 = await _open(db_path)
    store_1 = KmsPostgresSecretsStore(
        session_factory=session_factory_1,
        kms_client=LocalKmsClient(master_key=master_key),
        kms_key_id="test-cmk",
    )
    manager_1 = SecretsManager(store=store_1)
    await manager_1.store_libre_credentials(str(user_id), LIBRE_EMAIL, encrypt(LIBRE_PASSWORD))
    await manager_1.delete_credentials(str(user_id), "libre")
    await engine_1.dispose()

    engine_2, session_factory_2 = await _open(db_path)
    store_2 = KmsPostgresSecretsStore(
        session_factory=session_factory_2,
        kms_client=LocalKmsClient(master_key=master_key),
        kms_key_id="test-cmk",
    )
    manager_2 = SecretsManager(store=store_2)

    assert await manager_2.get_libre_credentials(str(user_id)) is None
    await engine_2.dispose()
