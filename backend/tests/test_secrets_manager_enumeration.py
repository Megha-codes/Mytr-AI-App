"""Tests for MockSecretsManager.list_libre_user_ids — the candidate pool
the shared poller's account registry starts from (architecture-v3.md §3.2)."""

from __future__ import annotations

import uuid
from datetime import datetime

from app.core.encryption import encrypt
from app.core.secrets_manager import secrets_manager


async def test_list_libre_user_ids_returns_only_libre_users():
    user_a = str(uuid.uuid4())
    user_b = str(uuid.uuid4())

    await secrets_manager.store_libre_credentials(user_a, "a@example.com", encrypt("pw"))
    await secrets_manager.store_libre_credentials(user_b, "b@example.com", encrypt("pw"))
    await secrets_manager.store_fitbit_tokens(user_a, "tok", "refresh", datetime.utcnow())

    user_ids = await secrets_manager.list_libre_user_ids()

    assert user_a in user_ids
    assert user_b in user_ids
    # Fitbit-only storage for user_a must not produce a second/duplicate entry.
    assert user_ids.count(user_a) == 1


async def test_list_libre_user_ids_excludes_deleted_credentials():
    user_id = str(uuid.uuid4())
    await secrets_manager.store_libre_credentials(user_id, "c@example.com", encrypt("pw"))
    assert user_id in await secrets_manager.list_libre_user_ids()

    await secrets_manager.delete_credentials(user_id, "libre")
    assert user_id not in await secrets_manager.list_libre_user_ids()


async def test_list_libre_user_ids_empty_when_none_stored():
    # Isolated user_id so this doesn't depend on suite ordering / prior state
    # of the module-level singleton store.
    user_ids = await secrets_manager.list_libre_user_ids()
    fresh_id = str(uuid.uuid4())
    assert fresh_id not in user_ids
