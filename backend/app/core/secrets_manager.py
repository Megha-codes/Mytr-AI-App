from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from .secrets_store import MockSecretsManager, SecretsStore


# ── FreeStyle Libre (LibreLinkUp credentials) ────────────────────────────────

@dataclass
class LibreCredentials:
    email:              str
    encrypted_password: str   # AES-256 via cryptography.fernet — never plain text


# ── Fitbit (OAuth2 tokens) ───────────────────────────────────────────────────

@dataclass
class FitbitCredentials:
    access_token:  str
    refresh_token: str
    expires_at:    datetime

# ── Garmin (OAuth 1.0a tokens) ───────────────────────────────────────────────

@dataclass
class GarminCredentials:
    oauth_token:        str
    oauth_token_secret: str


# ── Typed facade over a pluggable SecretsStore ────────────────────────────────

class SecretsManager:
    """The app-facing credential API. Backend-agnostic: everything here
    serializes typed credentials to/from plain dicts and delegates the
    actual storage to an injected `SecretsStore` (architecture-v3.md §4.3
    step 7) — `MockSecretsManager` for dev/test, `KmsPostgresSecretsStore`
    for production. Which one backs the module-level `secrets_manager`
    singleton below is chosen by `SECRETS_STORE_BACKEND` (see
    `_build_default_store`).

    Secret keys follow the convention:
      "libre:{user_id}"   →  LibreCredentials
      "fitbit:{user_id}"  →  FitbitCredentials
      "garmin:{user_id}"  →  GarminCredentials
    """

    def __init__(self, store: SecretsStore) -> None:
        self._store = store

    # Libre ──────────────────────────────────────────────────────────────────

    async def store_libre_credentials(
        self,
        user_id: str,
        email: str,
        encrypted_password: str,
    ) -> None:
        await self._store.store(
            f"libre:{user_id}",
            {"email": email, "encrypted_password": encrypted_password},
        )

    async def get_libre_credentials(
        self, user_id: str
    ) -> Optional[LibreCredentials]:
        raw = await self._store.get(f"libre:{user_id}")
        if raw is None:
            return None
        return LibreCredentials(email=raw["email"], encrypted_password=raw["encrypted_password"])

    async def list_libre_user_ids(self) -> list[str]:
        """user_ids with stored Libre credentials — the candidate pool for
        the shared poller's account registry (architecture-v3.md §3.2)."""
        return await self._store.list_user_ids("libre:")

    # Fitbit ─────────────────────────────────────────────────────────────────

    async def store_fitbit_tokens(
        self,
        user_id: str,
        access_token: str,
        refresh_token: str,
        expires_at: datetime,
    ) -> None:
        await self._store.store(
            f"fitbit:{user_id}",
            {
                "access_token": access_token,
                "refresh_token": refresh_token,
                "expires_at": expires_at.isoformat(),
            },
        )

    async def get_fitbit_credentials(
        self, user_id: str
    ) -> Optional[FitbitCredentials]:
        raw = await self._store.get(f"fitbit:{user_id}")
        if raw is None:
            return None
        return FitbitCredentials(
            access_token=raw["access_token"],
            refresh_token=raw["refresh_token"],
            expires_at=datetime.fromisoformat(raw["expires_at"]),
        )

    # Garmin ─────────────────────────────────────────────────────────────────

    async def store_garmin_tokens(
        self,
        user_id: str,
        oauth_token: str,
        oauth_token_secret: str,
    ) -> None:
        await self._store.store(
            f"garmin:{user_id}",
            {"oauth_token": oauth_token, "oauth_token_secret": oauth_token_secret},
        )

    async def get_garmin_credentials(
        self, user_id: str
    ) -> Optional[GarminCredentials]:
        raw = await self._store.get(f"garmin:{user_id}")
        if raw is None:
            return None
        return GarminCredentials(
            oauth_token=raw["oauth_token"], oauth_token_secret=raw["oauth_token_secret"]
        )

    # Generic Delete ─────────────────────────────────────────────────────────

    async def delete_credentials(self, user_id: str, device_type: str) -> None:
        """
        Wipes secrets for a specific device type.
        device_type should be "libre", "fitbit", or "garmin".
        """
        await self._store.delete(f"{device_type.lower()}:{user_id}")


# Module-level singleton — the app-wide credential API. Backend selection
# (MockSecretsManager vs. the durable KmsPostgresSecretsStore) is config-driven
# — see secrets_store_config.build_secrets_store, wired in below once that
# module exists.
secrets_manager = SecretsManager(store=MockSecretsManager())
