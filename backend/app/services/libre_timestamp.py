"""LibreLinkUp timestamp parsing: a US-style, timezone-less ``Timestamp`` string
("6/9/2024 3:45:12 PM") resolved against the account timezone and converted to a
UTC unix-epoch integer. This ambiguity is the single most likely place to
silently mis-store glucose data, so it lives in small pure functions with their
own tests.

⚠️ INTENTIONAL DUPLICATE — KEEP IN SYNC WITH THE DEVICE REPO ⚠️
    The standalone desk-device product carries a byte-for-byte-equivalent copy
    of these helpers inside its own ``libre_poller.py``. The two products are
    now independent codebases with no shared package, so this logic is
    duplicated on purpose. Any fix to Libre timestamp parsing MUST be applied to
    BOTH copies. See the matching note in the device repo's ``libre_poller.py``.
"""

from __future__ import annotations

import logging
import re
from datetime import datetime, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

logger = logging.getLogger("mytr.libre_timestamp")

_TIMESTAMP_RE = re.compile(
    r"^(\d{1,2})/(\d{1,2})/(\d{4}) (\d{1,2}):(\d{2}):(\d{2}) ?(AM|PM)$",
    re.IGNORECASE,
)


def parse_libre_timestamp(raw: str) -> datetime:
    """Parse a US-style, timezone-less Libre timestamp into a *naive* datetime.

    Format: ``M/D/YYYY H:MM:SS AM/PM`` e.g. "6/9/2024 3:45:12 PM". No timezone
    is attached here — the caller must resolve that (see
    ``libre_timestamp_to_epoch``). Raises ``ValueError`` if the string doesn't
    match, so a format change surfaces loudly instead of being silently
    mis-stored.
    """
    match = _TIMESTAMP_RE.match(raw.strip())
    if match is None:
        # Last-ditch: maybe Abbott switched to ISO-8601. Let fromisoformat try;
        # if that also fails it raises ValueError, which is what we want.
        return datetime.fromisoformat(raw.strip()).replace(tzinfo=None)

    month, day, year, hour, minute, second = (int(match.group(i)) for i in range(1, 7))
    meridiem = match.group(7).upper()
    if meridiem == "PM" and hour != 12:
        hour += 12
    elif meridiem == "AM" and hour == 12:
        hour = 0
    return datetime(year, month, day, hour, minute, second)


def _resolve_zone(tz_name: str | None) -> timezone | ZoneInfo:
    if not tz_name:
        logger.warning(
            "No account timezone set; interpreting naive Libre timestamps "
            "as UTC. Set the account's IANA timezone for correct conversion."
        )
        return timezone.utc
    try:
        return ZoneInfo(tz_name)
    except (ZoneInfoNotFoundError, ValueError):
        logger.warning("Unknown timezone %r; falling back to UTC.", tz_name)
        return timezone.utc


def libre_timestamp_to_epoch(raw: str, tz_name: str | None) -> int:
    """Convert a naive US-style Libre timestamp to a UTC unix-epoch integer.

    ``tz_name`` is the IANA timezone the account's timestamps are expressed in
    (e.g. "Asia/Kolkata"). The naive wall-clock time is localized to that zone
    and then converted to UTC, so the returned epoch is unambiguous regardless
    of where the backend itself runs.
    """
    naive = parse_libre_timestamp(raw)
    localized = naive.replace(tzinfo=_resolve_zone(tz_name))
    return int(localized.astimezone(timezone.utc).timestamp())
