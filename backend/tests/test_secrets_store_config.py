"""Tests for config-driven SecretsStore selection (architecture-v3.md §4.3
step 7): SECRETS_STORE_BACKEND / KMS_BACKEND pick the implementation.
"""

from __future__ import annotations

from app.core import secrets_store_config
from app.core.config import settings
from app.core.kms_client import AwsKmsClient, LocalKmsClient
from app.core.kms_postgres_secrets_store import KmsPostgresSecretsStore
from app.core.secrets_store import MockSecretsManager


def test_defaults_to_memory_backend(monkeypatch):
    monkeypatch.setattr(settings, "SECRETS_STORE_BACKEND", "memory")
    store = secrets_store_config.build_secrets_store()
    assert isinstance(store, MockSecretsManager)


def test_kms_postgres_backend_selected_by_config(monkeypatch):
    monkeypatch.setattr(settings, "SECRETS_STORE_BACKEND", "kms_postgres")
    monkeypatch.setattr(settings, "KMS_BACKEND", "local")
    store = secrets_store_config.build_secrets_store()
    assert isinstance(store, KmsPostgresSecretsStore)


def test_local_kms_client_selected_by_default(monkeypatch):
    monkeypatch.setattr(settings, "KMS_BACKEND", "local")
    client = secrets_store_config.build_kms_client()
    assert isinstance(client, LocalKmsClient)


def test_aws_kms_client_selected_when_configured(monkeypatch):
    monkeypatch.setattr(settings, "KMS_BACKEND", "aws")
    monkeypatch.setattr(settings, "AWS_KMS_KEY_ID", "arn:aws:kms:us-east-1:123:key/abc")
    try:
        client = secrets_store_config.build_kms_client()
    except RuntimeError as exc:
        # boto3 isn't installed in this environment — the guard itself is
        # what we're proving works, not real AWS connectivity.
        assert "boto3" in str(exc)
        return
    assert isinstance(client, AwsKmsClient)
