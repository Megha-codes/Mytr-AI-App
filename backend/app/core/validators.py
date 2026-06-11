"""
Lightweight, dependency-free input validation/normalization helpers.

Kept deliberately simple (no `email-validator` dependency). The regex is a
pragmatic format check, not full RFC 5322 — deliverability is verified by the
email-confirmation flow, not by parsing.
"""

import re

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def normalize_email(email: str) -> str:
    """Trim surrounding whitespace and lower-case the address so lookups and
    uniqueness checks are case-insensitive and consistent."""
    return (email or "").strip().lower()


def is_valid_email(email: str) -> bool:
    return bool(_EMAIL_RE.match((email or "").strip()))
