"""Shared test setup.

Supplies a dummy JWT_SECRET *before* any app module is imported (config /
security read env at import time), so the suite runs fully offline with no
Postgres / Timescale / real credentials. The CGM tests here use the in-memory
MockSecretsManager and httpx MockTransport, so no database is touched.
"""

from __future__ import annotations

import os

# Must be set before importing app.* (security.py raises if JWT_SECRET is
# missing; config reads env at import).
os.environ.setdefault("JWT_SECRET", "test-secret-not-used-anywhere-real")
