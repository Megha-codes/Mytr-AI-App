"""Tests for KmsPostgresSecretsStore (architecture-v3.md §4.3 step 7):
the durable, envelope-encrypted SecretsStore backend.
"""

from __future__ import annotations

from cryptography.fernet import Fernet
from sqlalchemy import select

from app.core.kms_client import LocalKmsClient
from app.core.kms_postgres_secrets_store import KmsPostgresSecretsStore
from app.core.secrets_store import SecretsStore
from app.models.secret import EncryptedSecret

from .conftest import build_sqlite_db


def _make_store(session_factory, master_key=None):
    kms_client = LocalKmsClient(master_key=master_key or Fernet.generate_key())
    return KmsPostgresSecretsStore(
        session_factory=session_factory, kms_client=kms_client, kms_key_id="local-test-key"
    ), kms_client


def test_kms_postgres_secrets_store_implements_secrets_store():
    assert issubclass(KmsPostgresSecretsStore, SecretsStore)


async def test_store_and_get_round_trip():
    engine, session_factory = await build_sqlite_db()
    store, _kms = _make_store(session_factory)

    await store.store("libre:user-1", {"email": "a@example.com", "encrypted_password": "cipher-blob"})
    value = await store.get("libre:user-1")

    assert value == {"email": "a@example.com", "encrypted_password": "cipher-blob"}
    await engine.dispose()


async def test_get_returns_none_for_unknown_key():
    engine, session_factory = await build_sqlite_db()
    store, _kms = _make_store(session_factory)

    assert await store.get("libre:nobody") is None
    await engine.dispose()


async def test_store_overwrites_existing_key():
    engine, session_factory = await build_sqlite_db()
    store, _kms = _make_store(session_factory)

    await store.store("libre:user-1", {"email": "old@example.com"})
    await store.store("libre:user-1", {"email": "new@example.com"})

    value = await store.get("libre:user-1")
    assert value == {"email": "new@example.com"}

    async with session_factory() as db:
        result = await db.execute(select(EncryptedSecret))
        assert len(result.scalars().all()) == 1  # overwritten, not duplicated
    await engine.dispose()


async def test_delete_removes_the_row():
    engine, session_factory = await build_sqlite_db()
    store, _kms = _make_store(session_factory)

    await store.store("libre:user-1", {"email": "a@example.com"})
    await store.delete("libre:user-1")

    assert await store.get("libre:user-1") is None
    async with session_factory() as db:
        result = await db.execute(select(EncryptedSecret))
        assert result.scalars().all() == []
    await engine.dispose()


async def test_delete_unknown_key_is_a_no_op():
    engine, session_factory = await build_sqlite_db()
    store, _kms = _make_store(session_factory)

    await store.delete("libre:nobody")  # must not raise
    await engine.dispose()


async def test_list_user_ids_filters_by_prefix():
    engine, session_factory = await build_sqlite_db()
    store, _kms = _make_store(session_factory)

    await store.store("libre:user-1", {"email": "a@example.com"})
    await store.store("libre:user-2", {"email": "b@example.com"})
    await store.store("fitbit:user-1", {"access_token": "tok"})

    libre_ids = await store.list_user_ids("libre:")
    assert set(libre_ids) == {"user-1", "user-2"}
    await engine.dispose()


async def test_ciphertext_and_wrapped_dek_are_never_the_plaintext_value():
    """The core envelope-encryption guarantee, checked directly against the
    raw row: neither stored column contains the plaintext email/password."""
    engine, session_factory = await build_sqlite_db()
    store, _kms = _make_store(session_factory)

    secret_value = {"email": "very-secret@example.com", "encrypted_password": "super-secret-cipher"}
    await store.store("libre:user-1", secret_value)

    async with session_factory() as db:
        result = await db.execute(select(EncryptedSecret).where(EncryptedSecret.key == "libre:user-1"))
        record = result.scalar_one()

    assert b"very-secret@example.com" not in record.ciphertext
    assert b"super-secret-cipher" not in record.wrapped_dek
    assert b"very-secret@example.com" not in record.wrapped_dek
    await engine.dispose()


async def test_get_returns_none_when_wrapped_dek_is_unreadable_by_this_kms_client():
    """A row wrapped under one master key must not be readable by a store
    configured with a different one — the same isolation the real KMS
    key-policy boundary would provide."""
    engine, session_factory = await build_sqlite_db()
    store_a, _ = _make_store(session_factory, master_key=Fernet.generate_key())
    store_b, _ = _make_store(session_factory, master_key=Fernet.generate_key())

    await store_a.store("libre:user-1", {"email": "a@example.com"})

    assert await store_b.get("libre:user-1") is None
    await engine.dispose()
