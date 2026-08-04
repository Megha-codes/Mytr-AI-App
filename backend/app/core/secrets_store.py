"""SecretsStore: the pluggable backend behind SecretsManager
(architecture-v3.md §4.3 step 7 / §1.6).

A generic key -> JSON-serializable-dict store. Keys follow the convention
"{credential_type}:{user_id}" (e.g. "libre:<uuid>"). Encoding/decoding into
typed dataclasses (LibreCredentials, etc.) is SecretsManager's job, one
layer up — the store itself knows nothing about credential shapes, which is
what makes it swappable.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional


class SecretsStore(ABC):
    @abstractmethod
    async def store(self, key: str, value: dict) -> None: ...

    @abstractmethod
    async def get(self, key: str) -> Optional[dict]: ...

    @abstractmethod
    async def delete(self, key: str) -> None: ...

    @abstractmethod
    async def list_user_ids(self, prefix: str) -> list[str]:
        """user_ids of every key starting with `prefix` (e.g. "libre:"),
        with the prefix stripped."""
        ...


class MockSecretsManager(SecretsStore):
    """In-memory SecretsStore for local dev and tests.

    Not durable — data is lost on process exit. That's the whole reason
    this pass exists: KmsPostgresSecretsStore (kms_postgres_secrets_store.py)
    is the durable, production replacement; which one backs the module-level
    `secrets_manager` singleton is chosen by config (see secrets_manager.py).
    """

    def __init__(self) -> None:
        self._store: dict[str, dict] = {}

    async def store(self, key: str, value: dict) -> None:
        self._store[key] = value

    async def get(self, key: str) -> Optional[dict]:
        return self._store.get(key)

    async def delete(self, key: str) -> None:
        self._store.pop(key, None)

    async def list_user_ids(self, prefix: str) -> list[str]:
        return [key[len(prefix):] for key in self._store if key.startswith(prefix)]
