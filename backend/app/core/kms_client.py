"""KmsClient: envelope-encryption key management for KmsPostgresSecretsStore
(architecture-v3.md §4.3 step 7).

Envelope encryption: every secret gets its own random Data Encryption Key
(DEK). The DEK encrypts the secret; KMS never sees the secret itself, only
the DEK. KMS's `GenerateDataKey` returns both the plaintext DEK (used once,
in memory, then discarded) and that same DEK encrypted ("wrapped") under a
KMS-managed master key. Only the wrapped form is ever persisted — reading a
secret back means asking KMS to unwrap it, so a raw database dump exposes
neither the secrets nor a usable key.
"""

from __future__ import annotations

import os
from abc import ABC, abstractmethod

from cryptography.fernet import Fernet


class KmsClient(ABC):
    @abstractmethod
    def generate_data_key(self) -> tuple[bytes, bytes]:
        """Returns (plaintext_dek, wrapped_dek). The plaintext key is never
        persisted by the caller — only used transiently to encrypt/decrypt,
        then dropped."""
        ...

    @abstractmethod
    def decrypt_data_key(self, wrapped_dek: bytes) -> bytes:
        """Unwraps a previously-generated DEK. This is the one operation
        that must go through KMS — it's what makes the wrapped key on disk
        useless without it."""
        ...


class LocalKmsClient(KmsClient):
    """Local KMS simulator for dev/test: wraps/unwraps data keys with a
    locally-held master key instead of calling AWS. Same envelope-encryption
    contract as AwsKmsClient — callers never see more than a transient
    plaintext DEK — so KmsPostgresSecretsStore behaves identically against
    either backend; only where the master key lives differs.

    The master key must be stable across restarts (set LOCAL_KMS_MASTER_KEY)
    or every previously-wrapped DEK becomes permanently unreadable — the
    same durability requirement as encryption.py's ENCRYPTION_KEY.
    """

    def __init__(self, master_key: bytes | None = None) -> None:
        raw = master_key or os.getenv("LOCAL_KMS_MASTER_KEY", "").encode()
        self._master_fernet = Fernet(raw if raw else Fernet.generate_key())

    def generate_data_key(self) -> tuple[bytes, bytes]:
        plaintext_dek = Fernet.generate_key()
        wrapped_dek = self._master_fernet.encrypt(plaintext_dek)
        return plaintext_dek, wrapped_dek

    def decrypt_data_key(self, wrapped_dek: bytes) -> bytes:
        return self._master_fernet.decrypt(wrapped_dek)


class AwsKmsClient(KmsClient):
    """Real AWS KMS backend. Requires `boto3` and an IAM principal with
    kms:GenerateDataKey / kms:Decrypt on `key_id`. Lazily imports boto3 so it
    isn't a hard dependency for environments that only ever run LocalKmsClient
    (dev, CI, this test suite)."""

    def __init__(self, key_id: str, region_name: str | None = None) -> None:
        if not key_id:
            raise ValueError("AwsKmsClient requires a KMS key_id (AWS_KMS_KEY_ID)")
        try:
            import boto3
        except ImportError as exc:
            raise RuntimeError(
                "AwsKmsClient requires the 'boto3' package (pip install boto3)"
            ) from exc
        self._key_id = key_id
        self._client = boto3.client("kms", region_name=region_name)

    def generate_data_key(self) -> tuple[bytes, bytes]:
        import base64

        response = self._client.generate_data_key(KeyId=self._key_id, KeySpec="AES_256")
        # AWS returns 32 raw bytes; Fernet needs a url-safe-base64 32-byte key.
        plaintext_dek = base64.urlsafe_b64encode(response["Plaintext"])
        return plaintext_dek, response["CiphertextBlob"]

    def decrypt_data_key(self, wrapped_dek: bytes) -> bytes:
        import base64

        response = self._client.decrypt(CiphertextBlob=wrapped_dek, KeyId=self._key_id)
        return base64.urlsafe_b64encode(response["Plaintext"])
