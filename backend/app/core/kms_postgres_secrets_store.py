"""KmsPostgresSecretsStore: the durable, production SecretsStore
(architecture-v3.md §4.3 step 7). Values are JSON-serialized and encrypted
under a per-record Data Encryption Key (envelope encryption via KmsClient —
see kms_client.py); only the wrapped DEK and the resulting ciphertext are
ever written to Postgres.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Optional

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy import select
from sqlalchemy.dialects import postgresql, sqlite

from ..models.secret import EncryptedSecret
from .kms_client import KmsClient
from .secrets_store import SecretsStore


def _insert_builder(dialect_name: str):
    # Mirrors LibreIngestionService's dialect dispatch: production runs on
    # Postgres, sqlite is a test-only stand-in (tests/conftest.py).
    return sqlite.insert if dialect_name == "sqlite" else postgresql.insert


class KmsPostgresSecretsStore(SecretsStore):
    def __init__(self, session_factory, kms_client: KmsClient, kms_key_id: Optional[str] = None) -> None:
        self._session_factory = session_factory
        self._kms_client = kms_client
        self._kms_key_id = kms_key_id

    async def store(self, key: str, value: dict) -> None:
        plaintext_dek, wrapped_dek = self._kms_client.generate_data_key()
        ciphertext = Fernet(plaintext_dek).encrypt(json.dumps(value).encode())

        async with self._session_factory() as db:
            insert = _insert_builder(db.bind.dialect.name)
            stmt = (
                insert(EncryptedSecret)
                .values(
                    key=key,
                    ciphertext=ciphertext,
                    wrapped_dek=wrapped_dek,
                    kms_key_id=self._kms_key_id,
                    updated_at=datetime.now(timezone.utc),
                )
                .on_conflict_do_update(
                    index_elements=["key"],
                    set_={
                        "ciphertext": ciphertext,
                        "wrapped_dek": wrapped_dek,
                        "kms_key_id": self._kms_key_id,
                        "updated_at": datetime.now(timezone.utc),
                    },
                )
            )
            await db.execute(stmt)
            await db.commit()

    async def get(self, key: str) -> Optional[dict]:
        async with self._session_factory() as db:
            result = await db.execute(select(EncryptedSecret).where(EncryptedSecret.key == key))
            record = result.scalar_one_or_none()
        if record is None:
            return None

        try:
            plaintext_dek = self._kms_client.decrypt_data_key(record.wrapped_dek)
            raw = Fernet(plaintext_dek).decrypt(record.ciphertext)
        except InvalidToken:
            # Wrong/rotated master key, or tampered ciphertext — treat as
            # unreadable rather than crash the caller.
            return None
        return json.loads(raw)

    async def delete(self, key: str) -> None:
        async with self._session_factory() as db:
            result = await db.execute(select(EncryptedSecret).where(EncryptedSecret.key == key))
            record = result.scalar_one_or_none()
            if record is not None:
                await db.delete(record)
                await db.commit()

    async def list_user_ids(self, prefix: str) -> list[str]:
        async with self._session_factory() as db:
            result = await db.execute(
                select(EncryptedSecret.key).where(EncryptedSecret.key.like(f"{prefix}%"))
            )
            keys = result.scalars().all()
        return [key[len(prefix):] for key in keys]
