"""
Symmetric encryption for sensitive credentials stored in Secrets Manager.

Dev:  a fresh Fernet key is generated each process start (not persistent —
      stored data becomes unreadable on restart, which is fine for dev).
Prod: set ENCRYPTION_KEY to a stable base64-encoded 32-byte key generated once
      with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
      Store it in AWS Secrets Manager or as an environment variable.

Requires: pip install cryptography
"""

import os
from cryptography.fernet import Fernet

_raw_key = os.getenv("ENCRYPTION_KEY", "").encode()
_fernet = Fernet(_raw_key if _raw_key else Fernet.generate_key())


def encrypt(plaintext: str) -> str:
    """Return a Fernet-encrypted, URL-safe base64 string."""
    return _fernet.encrypt(plaintext.encode()).decode()


def decrypt(ciphertext: str) -> str:
    """Decrypt a value produced by encrypt(). Raises InvalidToken on tamper."""
    return _fernet.decrypt(ciphertext.encode()).decode()
