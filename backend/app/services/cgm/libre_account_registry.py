"""Account registry for the shared Libre poller (architecture-v3.md §3.2 /
§4.3 step 3): which mytr.ai accounts should be polled, and how they group by
underlying Libre credential.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.encryption import decrypt
from ...core.secrets_manager import secrets_manager
from ...models.device import Device
from ...models.user import CGMDevice, LoginAttempt, User

logger = logging.getLogger("mytr.libre_account_registry")

# Without this bound, a user who connected Libre once and never opened the
# app or paired a desk device again would still generate unbounded Abbott
# API traffic forever — one HTTP round trip per poll interval, indefinitely.
RECENT_SESSION_WINDOW = timedelta(days=7)


@dataclass
class EligibleAccount:
    user_id: UUID
    email: str          # decrypted Libre login (the credential identity)
    password: str        # decrypted
    timezone: str        # users.timezone, for per-user timestamp resolution
    cgm_device_id: UUID  # target for the durable region_base cache


async def get_eligible_accounts(db: AsyncSession, secrets_mgr=None) -> list[EligibleAccount]:
    """Every user with stored Libre credentials AND an active Libre CGM
    connection, further bounded to accounts with an active desk device OR a
    successful login within the last 7 days.

    `secrets_mgr` defaults to the app-wide singleton; overridable so tests
    (and anything proving the registry repopulates from a specific durable
    store) can inject a differently-backed SecretsManager.
    """
    secrets_mgr = secrets_mgr or secrets_manager
    candidate_user_ids = await secrets_mgr.list_libre_user_ids()
    logger.warning("libre_account_registry: %d candidate(s) with stored Libre credentials", len(candidate_user_ids))
    if not candidate_user_ids:
        return []

    cutoff = datetime.utcnow() - RECENT_SESSION_WINDOW
    eligible: list[EligibleAccount] = []

    for raw_user_id in candidate_user_ids:
        try:
            user_id = UUID(raw_user_id)
        except ValueError:
            logger.warning("libre_account_registry: candidate %r is not a valid UUID, skipping", raw_user_id)
            continue

        user_result = await db.execute(select(User).where(User.id == user_id))
        user = user_result.scalar_one_or_none()
        if user is None:
            logger.warning("libre_account_registry: user %s not found (stale secret?), skipping", user_id)
            continue

        cgm_result = await db.execute(
            select(CGMDevice).where(
                CGMDevice.user_id == user_id,
                CGMDevice.device_type.like("LIBRE%"),
                CGMDevice.is_active.is_(True),
                CGMDevice.deleted_at.is_(None),
            )
        )
        cgm_device = cgm_result.scalar_one_or_none()
        if cgm_device is None:
            logger.warning("libre_account_registry: user %s has no active LIBRE cgm_devices row, skipping", user_id)
            continue

        device_result = await db.execute(
            select(Device).where(Device.user_id == user_id, Device.revoked_at.is_(None))
        )
        has_active_device = device_result.scalar_one_or_none() is not None

        has_recent_session = False
        if not has_active_device:
            login_result = await db.execute(
                select(LoginAttempt)
                .where(
                    func.lower(LoginAttempt.email) == user.email.lower(),
                    LoginAttempt.successful.is_(True),
                    LoginAttempt.created_at >= cutoff,
                )
                .limit(1)
            )
            has_recent_session = login_result.scalar_one_or_none() is not None

        if not (has_active_device or has_recent_session):
            logger.warning(
                "libre_account_registry: user %s has an active CGM connection but neither a "
                "paired desk device nor a successful login/refresh in the last %s — not eligible yet",
                user_id, RECENT_SESSION_WINDOW,
            )
            continue

        creds = await secrets_mgr.get_libre_credentials(raw_user_id)
        if creds is None:
            logger.warning("libre_account_registry: user %s has no stored Libre credentials despite being a candidate, skipping", user_id)
            continue
        try:
            password = decrypt(creds.encrypted_password)
        except Exception:
            logger.exception("libre_account_registry: could not decrypt stored credentials for user %s, skipping", user_id)
            continue

        logger.warning(
            "libre_account_registry: user %s is eligible (active_device=%s, recent_session=%s)",
            user_id, has_active_device, has_recent_session,
        )
        eligible.append(
            EligibleAccount(
                user_id=user_id,
                email=creds.email,
                password=password,
                timezone=user.timezone or "UTC",
                cgm_device_id=cgm_device.id,
            )
        )

    return eligible


def group_by_credential(accounts: list[EligibleAccount]) -> dict[str, list[EligibleAccount]]:
    """Groups accounts sharing the same underlying Libre login (email), so
    the ingestion service runs exactly one poll loop per distinct Libre
    account regardless of how many mytr.ai users follow it (e.g. family
    members sharing one LibreLinkUp login)."""
    groups: dict[str, list[EligibleAccount]] = {}
    for account in accounts:
        key = account.email.strip().lower()
        groups.setdefault(key, []).append(account)
    return groups
