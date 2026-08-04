"""Tests for the envelope-encryption KMS abstraction (architecture-v3.md
§4.3 step 7): LocalKmsClient is the dev/test stand-in for AwsKmsClient,
same contract — generate a data key, get back plaintext + wrapped forms,
and only the wrapped form should ever be usable without the master key.
"""

from __future__ import annotations

import pytest
from cryptography.fernet import Fernet, InvalidToken

from app.core.kms_client import AwsKmsClient, LocalKmsClient


def test_generate_data_key_returns_usable_plaintext_and_distinct_wrapped_form():
    kms = LocalKmsClient(master_key=Fernet.generate_key())
    plaintext_dek, wrapped_dek = kms.generate_data_key()

    assert plaintext_dek != wrapped_dek
    # The plaintext DEK must itself be a valid Fernet key (used to encrypt
    # the actual secret payload).
    Fernet(plaintext_dek)  # raises if malformed


def test_decrypt_data_key_recovers_the_same_plaintext():
    kms = LocalKmsClient(master_key=Fernet.generate_key())
    plaintext_dek, wrapped_dek = kms.generate_data_key()

    recovered = kms.decrypt_data_key(wrapped_dek)
    assert recovered == plaintext_dek


def test_each_data_key_is_unique():
    kms = LocalKmsClient(master_key=Fernet.generate_key())
    dek_1, _ = kms.generate_data_key()
    dek_2, _ = kms.generate_data_key()
    assert dek_1 != dek_2


def test_wrapped_dek_is_useless_without_the_master_key():
    """The whole point: a wrapped DEK captured from one KMS client instance
    must not be unwrappable by a client holding a different master key —
    proving the wrapping is doing real cryptographic work, not just
    bookkeeping."""
    kms_a = LocalKmsClient(master_key=Fernet.generate_key())
    kms_b = LocalKmsClient(master_key=Fernet.generate_key())

    _, wrapped_dek = kms_a.generate_data_key()

    with pytest.raises(InvalidToken):
        kms_b.decrypt_data_key(wrapped_dek)


def test_same_master_key_survives_a_simulated_restart():
    """A fresh LocalKmsClient instance built from the *same* master key
    (as would happen from LOCAL_KMS_MASTER_KEY surviving a process
    restart) must still unwrap DEKs it never generated itself."""
    master_key = Fernet.generate_key()
    kms_before_restart = LocalKmsClient(master_key=master_key)
    _, wrapped_dek = kms_before_restart.generate_data_key()

    kms_after_restart = LocalKmsClient(master_key=master_key)
    recovered = kms_after_restart.decrypt_data_key(wrapped_dek)
    Fernet(recovered)  # still a usable key


def test_aws_kms_client_requires_a_key_id():
    with pytest.raises(ValueError):
        AwsKmsClient(key_id="")
