-- 012_encrypted_secrets.sql
-- Architecture v3 §4.3 step 7 / §1.6 — durable, KMS-backed secrets store.
--
-- Replaces MockSecretsManager's in-process dict for production. Envelope
-- encryption: `ciphertext` is the credential payload encrypted under a
-- per-record Data Encryption Key (DEK); `wrapped_dek` is that DEK encrypted
-- by KMS. Neither column is decryptable without a live KMS call — a raw
-- read of this table exposes no credentials.

CREATE TABLE IF NOT EXISTS encrypted_secrets (
    key           TEXT PRIMARY KEY,        -- "{credential_type}:{user_id}", e.g. "libre:<uuid>"
    ciphertext    BYTEA NOT NULL,          -- credential payload, encrypted under the DEK
    wrapped_dek   BYTEA NOT NULL,          -- the DEK, encrypted ("wrapped") by KMS
    kms_key_id    TEXT,                    -- which KMS CMK wrapped this DEK (rotation/audit)
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
