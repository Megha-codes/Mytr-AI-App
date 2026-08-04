from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from uuid import UUID


class DevicePairStartRequest(BaseModel):
    hardware_id: str
    firmware_version: Optional[str] = None


class DevicePairStartResponse(BaseModel):
    code: str
    expires_in: int


class DevicePairPollRequest(BaseModel):
    hardware_id: str
    code: str


class DeviceTokens(BaseModel):
    device_access_token: str
    device_refresh_token: str
    user_id: str
    device_name: Optional[str] = None
    expires_in: int


class DeviceClaimRequest(BaseModel):
    code: str
    name: Optional[str] = None


class DeviceClaimResponse(BaseModel):
    device_id: UUID
    name: Optional[str] = None
    paired_at: Optional[datetime] = None


class DeviceListItem(BaseModel):
    device_id: UUID
    name: Optional[str] = None
    kind: str
    last_seen_at: Optional[datetime] = None
    firmware_version: Optional[str] = None
    paired_at: Optional[datetime] = None


class DeviceRenameRequest(BaseModel):
    name: str


class DeviceTokenRefreshRequest(BaseModel):
    refresh_token: str
