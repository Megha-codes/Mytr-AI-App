"""Structural test for migration 012: encrypted_secrets."""

from __future__ import annotations

from sqlalchemy import select

from app.models.secret import EncryptedSecret

from .conftest import build_sqlite_db


async def test_encrypted_secret_round_trips_binary_columns():
    engine, session_factory = await build_sqlite_db()
    async with session_factory() as session:
        record = EncryptedSecret(
            key="libre:user-1",
            ciphertext=b"\x00\x01opaque-ciphertext-bytes",
            wrapped_dek=b"\x02\x03opaque-wrapped-dek-bytes",
            kms_key_id="local",
        )
        session.add(record)
        await session.commit()

        result = await session.execute(select(EncryptedSecret).where(EncryptedSecret.key == "libre:user-1"))
        got = result.scalar_one()
        assert got.ciphertext == b"\x00\x01opaque-ciphertext-bytes"
        assert got.wrapped_dek == b"\x02\x03opaque-wrapped-dek-bytes"
        assert got.kms_key_id == "local"
        assert got.created_at is not None
    await engine.dispose()
