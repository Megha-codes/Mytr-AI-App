"""Tests for the highest-risk part of the CGM path: turning LibreLinkUp's
US-style, timezone-less timestamp string into a correct UTC epoch.

The timestamp format quirk ("6/9/2024 3:45:12 PM", no timezone) is exactly the
bug most likely to silently mis-store data, so it's covered thoroughly here.

NB: these helpers are an intentional duplicate of the desk-device repo's copy
(see app/services/libre_timestamp.py); any fix here must be mirrored there.
"""

from __future__ import annotations

from datetime import datetime, timezone

import pytest

from app.services.libre_timestamp import (
    libre_timestamp_to_epoch,
    parse_libre_timestamp,
)


def _epoch(y, mo, d, h, mi, s) -> int:
    """Expected UTC epoch, built independently from a UTC wall-clock time."""
    return int(datetime(y, mo, d, h, mi, s, tzinfo=timezone.utc).timestamp())


# ── parse_libre_timestamp: naive wall-clock extraction ────────────────────────
def test_parse_pm_afternoon():
    assert parse_libre_timestamp("6/9/2024 3:45:12 PM") == datetime(2024, 6, 9, 15, 45, 12)


def test_parse_am_morning():
    assert parse_libre_timestamp("6/9/2024 3:45:12 AM") == datetime(2024, 6, 9, 3, 45, 12)


def test_parse_noon_is_12pm():
    assert parse_libre_timestamp("6/9/2024 12:00:00 PM") == datetime(2024, 6, 9, 12, 0, 0)


def test_parse_midnight_is_12am():
    assert parse_libre_timestamp("6/9/2024 12:30:05 AM") == datetime(2024, 6, 9, 0, 30, 5)


def test_parse_single_digit_fields():
    assert parse_libre_timestamp("1/2/2024 1:05:09 AM") == datetime(2024, 1, 2, 1, 5, 9)


def test_parse_no_space_before_meridiem():
    # The reference regex tolerates a missing space before AM/PM.
    assert parse_libre_timestamp("6/9/2024 3:45:12PM") == datetime(2024, 6, 9, 15, 45, 12)


def test_parse_rejects_garbage():
    with pytest.raises(ValueError):
        parse_libre_timestamp("not a timestamp")


# ── libre_timestamp_to_epoch: timezone resolution -> UTC ──────────────────────
def test_epoch_new_york_summer_is_utc_minus_4():
    # 3:45:12 PM EDT (UTC-4) -> 19:45:12 UTC
    got = libre_timestamp_to_epoch("6/9/2024 3:45:12 PM", "America/New_York")
    assert got == _epoch(2024, 6, 9, 19, 45, 12)


def test_epoch_new_york_winter_is_utc_minus_5():
    # 3:45:12 PM EST (UTC-5) -> 20:45:12 UTC
    got = libre_timestamp_to_epoch("1/15/2024 3:45:12 PM", "America/New_York")
    assert got == _epoch(2024, 1, 15, 20, 45, 12)


def test_epoch_kolkata_is_utc_plus_5_30():
    # 3:45:12 PM IST (UTC+5:30) -> 10:15:12 UTC
    got = libre_timestamp_to_epoch("6/9/2024 3:45:12 PM", "Asia/Kolkata")
    assert got == _epoch(2024, 6, 9, 10, 15, 12)


def test_epoch_none_tz_treated_as_utc():
    got = libre_timestamp_to_epoch("6/9/2024 3:45:12 PM", None)
    assert got == _epoch(2024, 6, 9, 15, 45, 12)


def test_epoch_unknown_tz_falls_back_to_utc():
    got = libre_timestamp_to_epoch("6/9/2024 3:45:12 PM", "Mars/Olympus_Mons")
    assert got == _epoch(2024, 6, 9, 15, 45, 12)


def test_epoch_midnight_boundary_crosses_date_in_utc():
    # 1:00 AM IST on the 9th -> 19:30 UTC on the 8th, proving the date rolls
    # back correctly across the UTC boundary.
    got = libre_timestamp_to_epoch("6/9/2024 1:00:00 AM", "Asia/Kolkata")
    assert got == _epoch(2024, 6, 8, 19, 30, 0)
