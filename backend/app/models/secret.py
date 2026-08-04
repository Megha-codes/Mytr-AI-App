from sqlalchemy import Column, DateTime, LargeBinary, String, text

from ..database import Base


class EncryptedSecret(Base):
    """Durable, envelope-encrypted credential storage backing
    KmsPostgresSecretsStore (architecture-v3.md §4.3 step 7). `ciphertext`
    and `wrapped_dek` are opaque outside a live KMS call — see
    app/core/kms_client.py and app/core/kms_postgres_secrets_store.py."""

    __tablename__ = "encrypted_secrets"

    key = Column(String, primary_key=True)  # "{credential_type}:{user_id}"
    ciphertext = Column(LargeBinary, nullable=False)
    wrapped_dek = Column(LargeBinary, nullable=False)
    kms_key_id = Column(String)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=text("now()"))
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=text("now()"))
