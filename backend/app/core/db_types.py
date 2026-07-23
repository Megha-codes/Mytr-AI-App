"""Small portable column types shared by the device-pipeline models.

The rest of the backend targets Postgres directly (postgresql.UUID +
server_default gen_random_uuid()). The device pipeline additionally needs to
run on SQLite — for the fully-offline end-to-end proof and the pytest suite —
so its models use these dialect-aware types instead of Postgres-only ones.
On Postgres they map to native UUID; on SQLite they fall back to CHAR(36).
"""

from __future__ import annotations

import uuid

from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.types import CHAR, TypeDecorator


class GUID(TypeDecorator):
    """Platform-independent UUID.

    Uses Postgres' native UUID type when available, otherwise stores the
    stringified hex value in a CHAR(36). Values are always handed back to the
    application as ``uuid.UUID`` instances regardless of backend.
    """

    impl = CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == "postgresql":
            return dialect.type_descriptor(PG_UUID(as_uuid=True))
        return dialect.type_descriptor(CHAR(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if dialect.name == "postgresql":
            return value if isinstance(value, uuid.UUID) else uuid.UUID(str(value))
        return str(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return value if isinstance(value, uuid.UUID) else uuid.UUID(str(value))
