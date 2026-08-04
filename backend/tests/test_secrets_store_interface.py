"""Tests for the SecretsStore interface / SecretsManager facade split
(architecture-v3.md §4.3 step 7): SecretsManager is backend-agnostic, and
MockSecretsManager is a plain SecretsStore implementation swappable for a
durable one without any caller-visible change.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from app.core.secrets_manager import SecretsManager
from app.core.secrets_store import MockSecretsManager, SecretsStore


def test_mock_secrets_manager_implements_secrets_store():
    assert isinstance(MockSecretsManager(), SecretsStore)


async def test_generic_store_get_delete_round_trip():
    store = MockSecretsManager()
    await store.store("libre:abc", {"email": "a@example.com"})
    assert await store.get("libre:abc") == {"email": "a@example.com"}

    await store.delete("libre:abc")
    assert await store.get("libre:abc") is None


async def test_list_user_ids_strips_prefix():
    store = MockSecretsManager()
    await store.store("libre:user-1", {"email": "a@example.com"})
    await store.store("libre:user-2", {"email": "b@example.com"})
    await store.store("fitbit:user-1", {"access_token": "tok"})

    libre_ids = await store.list_user_ids("libre:")
    assert set(libre_ids) == {"user-1", "user-2"}


async def test_secrets_manager_is_backend_agnostic():
    """SecretsManager works identically regardless of which SecretsStore
    backs it — the whole point of the split. Proven here with a second,
    independent MockSecretsManager instance (not the module singleton)."""
    manager = SecretsManager(store=MockSecretsManager())
    user_id = str(uuid.uuid4())

    await manager.store_libre_credentials(user_id, "a@example.com", "cipher-blob")
    creds = await manager.get_libre_credentials(user_id)
    assert creds.email == "a@example.com"
    assert creds.encrypted_password == "cipher-blob"

    assert user_id in await manager.list_libre_user_ids()

    await manager.delete_credentials(user_id, "libre")
    assert await manager.get_libre_credentials(user_id) is None


async def test_secrets_manager_fitbit_and_garmin_round_trip():
    manager = SecretsManager(store=MockSecretsManager())
    user_id = str(uuid.uuid4())
    expires_at = datetime(2030, 1, 1, tzinfo=timezone.utc)

    await manager.store_fitbit_tokens(user_id, "access", "refresh", expires_at)
    fitbit = await manager.get_fitbit_credentials(user_id)
    assert fitbit.access_token == "access"
    assert fitbit.expires_at == expires_at

    await manager.store_garmin_tokens(user_id, "oauth-tok", "oauth-secret")
    garmin = await manager.get_garmin_credentials(user_id)
    assert garmin.oauth_token == "oauth-tok"
    assert garmin.oauth_token_secret == "oauth-secret"
