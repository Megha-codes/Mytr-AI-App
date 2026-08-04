"""Tests for the §2.6 envelope shape and builders."""

from __future__ import annotations

from datetime import datetime, timezone

from app.services.realtime import envelope as env


def test_build_envelope_shape():
    ts = datetime(2026, 7, 28, 9, 14, 3, tzinfo=timezone.utc)
    frame = env.build_envelope(env.FRAME_TYPE_PING, seq=7, data={}, ts=ts)

    assert frame == {
        "v": 1,
        "type": "ping",
        "ts": int(ts.timestamp()),
        "seq": 7,
        "data": {},
    }


def test_build_envelope_defaults_ts_to_now():
    before = datetime.now(timezone.utc)
    frame = env.build_envelope(env.FRAME_TYPE_HELLO, seq=0, data={})
    after = datetime.now(timezone.utc)

    assert int(before.timestamp()) <= frame["ts"] <= int(after.timestamp())


def test_build_glucose_reading_data_matches_the_documented_shape():
    ts = datetime(2026, 7, 28, 9, 14, 3, tzinfo=timezone.utc)
    data = env.build_glucose_reading_data(
        ts=ts, mgdl=132, trend="flat", trend_arrow="→", sensor_id="a1b2c3", source="LIBRE",
    )
    assert data == {
        "ts": int(ts.timestamp()),
        "mgdl": 132,
        "trend": "flat",
        "trend_arrow": "→",
        "sensor_id": "a1b2c3",
        "source": "LIBRE",
    }


def test_build_glucose_reading_data_allows_null_sensor_and_trend_for_manual_entries():
    ts = datetime.now(timezone.utc)
    data = env.build_glucose_reading_data(
        ts=ts, mgdl=110, trend=None, trend_arrow="→", sensor_id=None, source="MANUAL",
    )
    assert data["sensor_id"] is None
    assert data["trend"] is None
    assert data["source"] == "MANUAL"


def test_build_glucose_state_data():
    since = datetime(2026, 7, 28, 9, 0, 0, tzinfo=timezone.utc)
    data = env.build_glucose_state_data("LIVE", since)
    assert data == {"state": "LIVE", "since": since.isoformat()}


def test_build_hello_data_shape():
    data = env.build_hello_data(seq=42)
    assert set(data.keys()) == {"server_time", "seq", "heartbeat_s"}
    assert data["seq"] == 42
    assert data["heartbeat_s"] == 30
    # server_time must be a real, parseable ISO timestamp.
    datetime.fromisoformat(data["server_time"])


def test_resync_frame_is_a_bare_marker_not_an_envelope():
    assert env.RESYNC_FRAME == {"type": "resync"}


def test_all_documented_frame_types_are_defined():
    documented = {
        env.FRAME_TYPE_HELLO,
        env.FRAME_TYPE_GLUCOSE_READING,
        env.FRAME_TYPE_GLUCOSE_STATE,
        env.FRAME_TYPE_HEALTH_UPDATED,
        env.FRAME_TYPE_CALORIES_UPDATED,
        env.FRAME_TYPE_DEVICE_COMMAND,
        env.FRAME_TYPE_PING,
    }
    assert len(documented) == 7  # all distinct, none accidentally aliased
