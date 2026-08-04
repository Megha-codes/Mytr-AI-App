from dataclasses import dataclass
from datetime import datetime
from typing import Optional


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

# ── Mock store (replace with boto3 AWS Secrets Manager in prod) ──────────────

class MockSecretsManager:
    """
    In-memory store for local dev.
    In production, replace with a boto3 client that calls
    secretsmanager.put_secret_value / get_secret_value.
    Secret names follow the convention:
      "libre:{user_id}"   →  LibreCredentials
      "fitbit:{user_id}"  →  FitbitCredentials
      "garmin:{user_id}"  →  GarminCredentials
    """

    def __init__(self) -> None:
        self._store: dict = {}

    # Libre ──────────────────────────────────────────────────────────────────

    async def store_libre_credentials(
        self,
        user_id: str,
        email: str,
        encrypted_password: str,
    ) -> None:
        self._store[f"libre:{user_id}"] = LibreCredentials(
            email=email,
            encrypted_password=encrypted_password,
        )

    async def get_libre_credentials(
        self, user_id: str
    ) -> Optional[LibreCredentials]:
        return self._store.get(f"libre:{user_id}")

    async def list_libre_user_ids(self) -> list[str]:
        """user_ids with stored Libre credentials — the candidate pool for
        the shared poller's account registry (architecture-v3.md §3.2)."""
        return [
            key.split(":", 1)[1]
            for key in self._store
            if key.startswith("libre:")
        ]

    # Fitbit ─────────────────────────────────────────────────────────────────

    async def store_fitbit_tokens(
        self,
        user_id: str,
        access_token: str,
        refresh_token: str,
        expires_at: datetime,
    ) -> None:
        self._store[f"fitbit:{user_id}"] = FitbitCredentials(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_at=expires_at,
        )

    async def get_fitbit_credentials(
        self, user_id: str
    ) -> Optional[FitbitCredentials]:
        return self._store.get(f"fitbit:{user_id}")

    # Garmin ─────────────────────────────────────────────────────────────────

    async def store_garmin_tokens(
        self,
        user_id: str,
        oauth_token: str,
        oauth_token_secret: str,
    ) -> None:
        self._store[f"garmin:{user_id}"] = GarminCredentials(
            oauth_token=oauth_token,
            oauth_token_secret=oauth_token_secret,
        )

    async def get_garmin_credentials(
        self, user_id: str
    ) -> Optional[GarminCredentials]:
        return self._store.get(f"garmin:{user_id}")

    # Generic Delete ─────────────────────────────────────────────────────────

    async def delete_credentials(self, user_id: str, device_type: str) -> None:
        """
        Wipes secrets for a specific device type.
        device_type should be "libre", "fitbit", or "garmin".
        """
        key = f"{device_type.lower()}:{user_id}"
        if key in self._store:
            del self._store[key]


# Module-level singleton — swap for a real AWS client at deploy time
secrets_manager = MockSecretsManager()
