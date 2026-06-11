"""
Server-side password policy. The frontend mirrors these rules for UX, but this
is the authoritative check — never trust client-side validation alone.

Rules: at least MIN_LENGTH characters, at least one letter, at least one digit,
and not a well-known common password.
"""

import re
from pathlib import Path
from typing import Optional

MIN_LENGTH = 8

# The most common passwords. This is a compact starter set; for production,
# drop the full SecLists "10k-most-common.txt" into the data file referenced
# below and it will be merged in automatically.
_BUILTIN_COMMON = {
    "password", "password1", "password123", "passw0rd", "123456", "1234567",
    "12345678", "123456789", "1234567890", "12345", "qwerty", "qwerty123",
    "abc123", "111111", "000000", "letmein", "welcome", "welcome1", "admin",
    "admin123", "iloveyou", "monkey", "dragon", "sunshine", "princess",
    "football", "baseball", "trustno1", "whatever", "qazwsx", "qwertyuiop",
    "asdfghjkl", "zxcvbnm", "1q2w3e4r", "1qaz2wsx", "changeme", "secret",
    "test1234", "pass1234", "mytrai", "mytrai123", "diabetes", "glucose",
}

_DATA_FILE = Path(__file__).resolve().parent / "data" / "common_passwords.txt"


def _load_common_passwords() -> frozenset:
    passwords = set(_BUILTIN_COMMON)
    try:
        if _DATA_FILE.exists():
            with _DATA_FILE.open("r", encoding="utf-8", errors="ignore") as fh:
                passwords.update(line.strip().lower() for line in fh if line.strip())
    except OSError:
        pass
    return frozenset(passwords)


_COMMON_PASSWORDS = _load_common_passwords()


def validate_password(password: str) -> Optional[str]:
    """Return a human-readable error message if the password is unacceptable,
    or None if it satisfies the policy."""
    if not password or len(password) < MIN_LENGTH:
        return f"Password must be at least {MIN_LENGTH} characters long."
    if not re.search(r"[A-Za-z]", password):
        return "Password must contain at least one letter."
    if not re.search(r"\d", password):
        return "Password must contain at least one number."
    if password.lower() in _COMMON_PASSWORDS:
        return "This password is too common. Please choose something less guessable."
    return None
