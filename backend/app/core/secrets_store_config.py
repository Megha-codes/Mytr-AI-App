"""Config-driven SecretsStore selection (architecture-v3.md §4.3 step 7).
The one place that reads SECRETS_STORE_BACKEND / KMS_BACKEND — everything
else just uses whatever `secrets_manager.py`'s module-level singleton ends
up wired to.
"""

from __future__ import annotations

from .config import settings
from .kms_client import AwsKmsClient, KmsClient, LocalKmsClient
from .kms_postgres_secrets_store import KmsPostgresSecretsStore
from .secrets_store import MockSecretsManager, SecretsStore


def build_kms_client() -> KmsClient:
    if settings.KMS_BACKEND == "aws":
        return AwsKmsClient(key_id=settings.AWS_KMS_KEY_ID)
    master_key = settings.LOCAL_KMS_MASTER_KEY.encode() if settings.LOCAL_KMS_MASTER_KEY else None
    return LocalKmsClient(master_key=master_key)


def build_secrets_store() -> SecretsStore:
    if settings.SECRETS_STORE_BACKEND == "kms_postgres":
        from ..database import AsyncSessionLocal

        return KmsPostgresSecretsStore(
            session_factory=AsyncSessionLocal,
            kms_client=build_kms_client(),
            kms_key_id=settings.AWS_KMS_KEY_ID or None,
        )
    return MockSecretsManager()
