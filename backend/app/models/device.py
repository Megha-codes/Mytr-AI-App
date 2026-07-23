"""SQLAlchemy models for the mytr-desk device pipeline.

Three tables:

- ``devices``          one row per paired desk device; holds the hashed device
                       bearer token used to auth the stream / backfill / voice
                       endpoints, and the user it was claimed by.
- ``pairing_sessions`` short-lived QR pairing handshakes: the device opens one
                       and polls it; the mobile app claims it for a user.
- ``device_readings``  the reading store the poller writes and the stream /
                       backfill serve, in the exact wire shape syncd expects
                       (ts / mgdl / trend / sensor_id).

These live on their own DeviceBase/engine (see app/device_database.py) so the
store can run on SQLite for the offline proof and tests; in production they
sit in the main Postgres alongside ``users``.
"""

from __future__ import annotations

import uuid

from sqlalchemy import (
    BigInteger,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    PrimaryKeyConstraint,
    String,
    func,
)

from ..core.db_types import GUID
from ..device_database import DeviceBase


class Device(DeviceBase):
    """A paired desk device. Auth = the (hashed) device bearer token."""

    __tablename__ = "devices"

    id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    # user_id is nullable at row-creation but always set by the time a token is
    # issued (a device is only ever tokenised through a user's claim). The
    # devices.user_id -> users.id foreign key is declared in migrations/010 (it
    # spans the main-app tables, which aren't part of this store's metadata).
    user_id = Column(GUID(), nullable=True)
    # SHA-256 hex of the bearer token — the raw token is returned to the device
    # exactly once at claim time and never stored, so it can't leak from the db.
    token_hash = Column(String, unique=True, nullable=False, index=True)
    name = Column(String)
    # The Libre sensor this device is bound to, when known. Informational: the
    # stream/backfill serve every sensor's readings, matching the mock backend.
    sensor_id = Column(String)
    paired_at = Column(DateTime, server_default=func.now())
    last_seen_at = Column(DateTime)
    revoked_at = Column(DateTime)


class PairingSession(DeviceBase):
    """A QR pairing handshake.

    The device POSTs /v1/devices/pair to open one (status ``pending``) and
    renders ``pairing_code`` as a QR. The mobile app POSTs the code to
    /v1/devices/pair/claim, which flips it to ``claimed`` and mints the device
    token. The device's next poll of /v1/devices/pair returns that token.
    """

    __tablename__ = "pairing_sessions"

    id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    # Short, human-shaped code embedded in the QR and typed/scanned by the app.
    pairing_code = Column(String, unique=True, nullable=False, index=True)
    status = Column(String, nullable=False, default="pending")  # pending|claimed|consumed
    device_id = Column(GUID(), ForeignKey("devices.id", ondelete="SET NULL"), nullable=True)
    # Raw device token, held transiently between claim and the device's next
    # poll, then cleared (status -> consumed). This is the one place a raw token
    # exists at rest, and only for seconds; everywhere else only its hash lives.
    device_token = Column(String)
    created_at = Column(DateTime, server_default=func.now())
    expires_at = Column(DateTime, nullable=False)
    claimed_at = Column(DateTime)


class DeviceReading(DeviceBase):
    """One glucose reading, in the exact shape syncd consumes.

    ``ts`` is unix epoch **seconds, UTC** — the poller resolves the Libre
    account timezone and converts before writing, so a raw Libre timestamp
    string never reaches this table. ``trend`` is our own string label
    (flat/rising/rising_rapid/falling/falling_rapid), already translated from
    LibreLinkUp's 1-5 TrendArrow. Dedup key is (sensor_id, ts): the poller
    re-pulls overlapping ~12h graph windows every minute and relies on this to
    ignore readings it already stored.
    """

    __tablename__ = "device_readings"
    __table_args__ = (
        PrimaryKeyConstraint("sensor_id", "ts"),
        Index("idx_device_readings_ts", "ts"),
    )

    ts = Column(BigInteger, nullable=False)
    mgdl = Column(Float, nullable=False)
    trend = Column(String)
    sensor_id = Column(String, nullable=False)
    created_at = Column(DateTime, server_default=func.now())
