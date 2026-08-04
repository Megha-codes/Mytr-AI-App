from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, text
from sqlalchemy.dialects.postgresql import UUID
from ..database import Base


class Device(Base):
    """A physical desk unit — distinct from `CGMDevice`, which models a
    user's CGM sensor connection. A device is display-only: it never holds
    Libre credentials, only its own pairing tokens."""

    __tablename__ = "devices"

    id = Column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))  # NULL until paired
    hardware_id = Column(String, nullable=False, unique=True)  # Pi serial from /proc/cpuinfo
    kind = Column(String, nullable=False, server_default=text("'DESK'"))
    name = Column(String)  # user-editable, "Bedside"
    firmware_version = Column(String)
    # Bumped to revoke this device's tokens (unpair, or the user's logout-all).
    token_version = Column(Integer, nullable=False, server_default=text("0"))
    paired_at = Column(DateTime(timezone=True))
    last_seen_at = Column(DateTime(timezone=True))
    revoked_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=text("now()"))


class DevicePairingCode(Base):
    """Short-lived, single-use pairing code. Device-initiated: the device
    generates nothing secret, the backend does."""

    __tablename__ = "device_pairing_codes"

    code = Column(String, primary_key=True)  # 8 chars, Crockford base32, no vowels
    hardware_id = Column(String, nullable=False)
    device_id = Column(UUID(as_uuid=True), ForeignKey("devices.id", ondelete="CASCADE"))
    claimed_by = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    expires_at = Column(DateTime(timezone=True), nullable=False)  # now() + 10 minutes
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=text("now()"))
