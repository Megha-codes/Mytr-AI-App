"""Tests for resolve_glucose_state (architecture-v3.md §2.4) — the
load-bearing device state the renderer must never fake a number around."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.services.realtime.glucose_state import resolve_glucose_state


class _Device:
    def __init__(self, is_active=True, sensor_status="ACTIVE"):
        self.is_active = is_active
        self.sensor_status = sensor_status


class _Reading:
    def __init__(self, recorded_at):
        self.recorded_at = recorded_at


NOW = datetime(2026, 8, 1, 12, 0, tzinfo=timezone.utc)


def test_no_active_device_is_not_connected():
    assert resolve_glucose_state(None, None, now=NOW) == "NOT_CONNECTED"


def test_inactive_device_is_not_connected():
    device = _Device(is_active=False)
    reading = _Reading(NOW - timedelta(minutes=1))
    assert resolve_glucose_state(device, reading, now=NOW) == "NOT_CONNECTED"


def test_expired_sensor_is_no_sensor_even_with_a_reading():
    device = _Device(sensor_status="EXPIRED")
    reading = _Reading(NOW - timedelta(minutes=1))
    assert resolve_glucose_state(device, reading, now=NOW) == "NO_SENSOR"


def test_active_device_with_no_reading_yet_is_no_sensor():
    device = _Device()
    assert resolve_glucose_state(device, None, now=NOW) == "NO_SENSOR"


def test_fresh_reading_is_live():
    device = _Device()
    reading = _Reading(NOW - timedelta(minutes=9, seconds=59))
    assert resolve_glucose_state(device, reading, now=NOW) == "LIVE"


def test_reading_at_exactly_ten_minutes_is_stale():
    device = _Device()
    reading = _Reading(NOW - timedelta(minutes=10))
    assert resolve_glucose_state(device, reading, now=NOW) == "STALE"


def test_old_reading_is_stale():
    device = _Device()
    reading = _Reading(NOW - timedelta(hours=2))
    assert resolve_glucose_state(device, reading, now=NOW) == "STALE"


def test_naive_recorded_at_is_treated_as_utc():
    device = _Device()
    reading = _Reading(datetime(2026, 8, 1, 11, 59))  # no tzinfo
    assert resolve_glucose_state(device, reading, now=NOW) == "LIVE"
