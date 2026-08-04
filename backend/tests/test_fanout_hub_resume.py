"""Tests for FanoutHub.resume() — the reconnect recovery path (§2.6):
`{"type":"resume","since_seq":N}` either replays what was missed from the
glucose_readings store, or tells the client to resync.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from app.models.glucose_reading import GlucoseReadingModel
from app.services.realtime.fanout_hub import FanoutHub

from .conftest import build_sqlite_timescale_db


async def _insert_reading(session_factory, user_id, recorded_at, value=100, sensor_id="s1"):
    async with session_factory() as session:
        session.add(GlucoseReadingModel(
            id=uuid.uuid4(), user_id=user_id, value_mgdl=value, trend="STABLE",
            trend_arrow="→", device_type="LIBRE", is_continuous=True,
            recorded_at=recorded_at, sensor_id=sensor_id, source="LIBRE",
        ))
        await session.commit()


async def test_already_caught_up_returns_no_envelopes():
    engine, session_factory = await build_sqlite_timescale_db()
    hub = FanoutHub()
    user_id = uuid.uuid4()
    hub.publish_glucose_reading(
        user_id, recorded_at=datetime.now(timezone.utc), mgdl=100,
        trend="STABLE", trend_arrow="→", sensor_id="s1", source="LIBRE",
    )

    result = await hub.resume(user_id, since_seq=hub.current_seq(user_id), session_factory=session_factory)

    assert result.resync is False
    assert result.envelopes == []
    await engine.dispose()


async def test_since_seq_zero_replays_the_full_resume_window():
    engine, session_factory = await build_sqlite_timescale_db()
    hub = FanoutHub()
    user_id = uuid.uuid4()
    now = datetime.now(timezone.utc)

    await _insert_reading(session_factory, user_id, now - timedelta(minutes=30), value=110)
    await _insert_reading(session_factory, user_id, now - timedelta(minutes=10), value=120)
    hub.publish(user_id, "glucose.reading", {})  # advances seq so current != 0

    result = await hub.resume(user_id, since_seq=0, session_factory=session_factory)

    assert result.resync is False
    values = [e["data"]["mgdl"] for e in result.envelopes]
    assert values == [110, 120]
    await engine.dispose()


async def test_since_seq_zero_excludes_readings_older_than_24h():
    engine, session_factory = await build_sqlite_timescale_db()
    hub = FanoutHub()
    user_id = uuid.uuid4()
    now = datetime.now(timezone.utc)

    await _insert_reading(session_factory, user_id, now - timedelta(hours=30), value=999)  # too old
    await _insert_reading(session_factory, user_id, now - timedelta(hours=1), value=115)
    hub.publish(user_id, "glucose.reading", {})

    result = await hub.resume(user_id, since_seq=0, session_factory=session_factory)

    values = [e["data"]["mgdl"] for e in result.envelopes]
    assert values == [115]
    await engine.dispose()


async def test_resume_replays_only_readings_missed_after_the_checkpoint():
    """The core scenario: a subscriber sees reading 1, then misses readings
    2 and 3 while disconnected. Resuming from reading 1's seq must return
    exactly readings 2 and 3, in order — not reading 1 again."""
    engine, session_factory = await build_sqlite_timescale_db()
    hub = FanoutHub()
    user_id = uuid.uuid4()
    now = datetime.now(timezone.utc)
    t1, t2, t3 = now - timedelta(minutes=20), now - timedelta(minutes=10), now - timedelta(minutes=1)

    await _insert_reading(session_factory, user_id, t1, value=101)
    checkpoint_envelope = hub.publish_glucose_reading(
        user_id, recorded_at=t1, mgdl=101, trend="STABLE", trend_arrow="→",
        sensor_id="s1", source="LIBRE",
    )
    since_seq = checkpoint_envelope["seq"]

    # Missed while disconnected:
    await _insert_reading(session_factory, user_id, t2, value=102)
    hub.publish_glucose_reading(
        user_id, recorded_at=t2, mgdl=102, trend="STABLE", trend_arrow="→",
        sensor_id="s1", source="LIBRE",
    )
    await _insert_reading(session_factory, user_id, t3, value=103)
    hub.publish_glucose_reading(
        user_id, recorded_at=t3, mgdl=103, trend="STABLE", trend_arrow="→",
        sensor_id="s1", source="LIBRE",
    )

    result = await hub.resume(user_id, since_seq=since_seq, session_factory=session_factory)

    assert result.resync is False
    values = [e["data"]["mgdl"] for e in result.envelopes]
    assert values == [102, 103]
    for envelope in result.envelopes:
        assert envelope["type"] == "glucose.reading"
    await engine.dispose()


async def test_resume_isolates_by_user():
    engine, session_factory = await build_sqlite_timescale_db()
    hub = FanoutHub()
    user_a = uuid.uuid4()
    user_b = uuid.uuid4()
    now = datetime.now(timezone.utc)

    await _insert_reading(session_factory, user_a, now - timedelta(minutes=5), value=150)
    await _insert_reading(session_factory, user_b, now - timedelta(minutes=5), value=250)
    hub.publish(user_a, "glucose.reading", {})
    hub.publish(user_b, "glucose.reading", {})

    result = await hub.resume(user_a, since_seq=0, session_factory=session_factory)

    values = [e["data"]["mgdl"] for e in result.envelopes]
    assert values == [150]
    await engine.dispose()


async def test_unknown_since_seq_triggers_resync():
    engine, session_factory = await build_sqlite_timescale_db()
    hub = FanoutHub()
    user_id = uuid.uuid4()
    # Two generic (non-glucose.reading) publishes: seq advances to 2, but
    # neither recorded a checkpoint, so since_seq=1 — behind current, but
    # unrecognized — can't be reconciled.
    hub.publish(user_id, "glucose.reading", {})
    hub.publish(user_id, "glucose.reading", {})

    result = await hub.resume(user_id, since_seq=1, session_factory=session_factory)

    assert result.resync is True
    assert result.envelopes == []
    await engine.dispose()


async def test_since_seq_beyond_current_triggers_resync():
    engine, session_factory = await build_sqlite_timescale_db()
    hub = FanoutHub()
    user_id = uuid.uuid4()
    hub.publish(user_id, "glucose.reading", {})

    result = await hub.resume(user_id, since_seq=999, session_factory=session_factory)

    assert result.resync is True
    await engine.dispose()


async def test_negative_since_seq_triggers_resync():
    engine, session_factory = await build_sqlite_timescale_db()
    hub = FanoutHub()
    user_id = uuid.uuid4()

    result = await hub.resume(user_id, since_seq=-1, session_factory=session_factory)

    assert result.resync is True
    await engine.dispose()


async def test_resume_for_a_user_the_hub_has_never_seen_with_since_seq_zero():
    """A brand-new client that's never received anything yet — since_seq=0
    against a user_id the hub has no history for at all must not crash, and
    must fall back to whatever the store has (nothing, here)."""
    engine, session_factory = await build_sqlite_timescale_db()
    hub = FanoutHub()
    user_id = uuid.uuid4()

    result = await hub.resume(user_id, since_seq=0, session_factory=session_factory)

    assert result.resync is False
    assert result.envelopes == []
    await engine.dispose()
