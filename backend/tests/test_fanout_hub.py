"""Tests for FanoutHub's core pub/sub (architecture-v3.md §2.6): subscribe,
publish, per-user seq, and isolation between users. Resume/replay is covered
separately in test_fanout_hub_resume.py.
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import datetime, timezone

from app.services.realtime.fanout_hub import FanoutHub


def _drain(queue: asyncio.Queue) -> list[dict]:
    items = []
    while not queue.empty():
        items.append(queue.get_nowait())
    return items


async def test_subscriber_receives_a_published_event():
    hub = FanoutHub()
    user_id = uuid.uuid4()
    queue = hub.subscribe(user_id)

    envelope = hub.publish(user_id, "ping", {})

    received = await queue.get()
    assert received == envelope


async def test_two_subscribers_on_the_same_user_both_receive_events_in_order():
    hub = FanoutHub()
    user_id = uuid.uuid4()
    queue_a = hub.subscribe(user_id)
    queue_b = hub.subscribe(user_id)

    first = hub.publish(user_id, "ping", {"n": 1})
    second = hub.publish(user_id, "ping", {"n": 2})

    assert _drain(queue_a) == [first, second]
    assert _drain(queue_b) == [first, second]


async def test_subscriber_on_a_different_user_receives_nothing():
    hub = FanoutHub()
    user_a = uuid.uuid4()
    user_b = uuid.uuid4()
    queue_b = hub.subscribe(user_b)

    hub.publish(user_a, "ping", {})

    assert queue_b.empty()


async def test_unsubscribe_stops_delivery():
    hub = FanoutHub()
    user_id = uuid.uuid4()
    queue = hub.subscribe(user_id)
    hub.unsubscribe(user_id, queue)

    hub.publish(user_id, "ping", {})

    assert queue.empty()


async def test_unsubscribe_unknown_queue_is_a_no_op():
    hub = FanoutHub()
    user_id = uuid.uuid4()
    stray_queue: asyncio.Queue = asyncio.Queue()

    hub.unsubscribe(user_id, stray_queue)  # never subscribed — must not raise


async def test_seq_is_monotonic_per_user_and_independent_across_users():
    hub = FanoutHub()
    user_a = uuid.uuid4()
    user_b = uuid.uuid4()

    a1 = hub.publish(user_a, "ping", {})
    b1 = hub.publish(user_b, "ping", {})
    a2 = hub.publish(user_a, "ping", {})

    assert a1["seq"] == 1
    assert a2["seq"] == 2
    assert b1["seq"] == 1  # independent counter, unaffected by user_a's publishes


async def test_seq_advances_even_with_no_subscribers():
    hub = FanoutHub()
    user_id = uuid.uuid4()

    first = hub.publish(user_id, "ping", {})
    assert first["seq"] == 1
    assert hub.current_seq(user_id) == 1


def test_subscriber_count():
    hub = FanoutHub()
    user_id = uuid.uuid4()
    assert hub.subscriber_count(user_id) == 0

    q1 = hub.subscribe(user_id)
    q2 = hub.subscribe(user_id)
    assert hub.subscriber_count(user_id) == 2

    hub.unsubscribe(user_id, q1)
    assert hub.subscriber_count(user_id) == 1

    hub.unsubscribe(user_id, q2)
    assert hub.subscriber_count(user_id) == 0


async def test_publish_glucose_reading_matches_documented_envelope():
    hub = FanoutHub()
    user_id = uuid.uuid4()
    recorded_at = datetime(2026, 7, 28, 9, 14, 3, tzinfo=timezone.utc)

    envelope = hub.publish_glucose_reading(
        user_id, recorded_at=recorded_at, mgdl=132, trend="flat",
        trend_arrow="→", sensor_id="a1b2c3", source="LIBRE",
    )

    assert envelope["v"] == 1
    assert envelope["type"] == "glucose.reading"
    assert envelope["seq"] == 1
    assert envelope["data"] == {
        "ts": int(recorded_at.timestamp()),
        "mgdl": 132,
        "trend": "flat",
        "trend_arrow": "→",
        "sensor_id": "a1b2c3",
        "source": "LIBRE",
    }


async def test_publish_glucose_state():
    hub = FanoutHub()
    user_id = uuid.uuid4()
    since = datetime.now(timezone.utc)

    envelope = hub.publish_glucose_state(user_id, state="LIVE", since=since)

    assert envelope["type"] == "glucose.state"
    assert envelope["data"] == {"state": "LIVE", "since": since.isoformat()}


def test_build_hello_reflects_current_seq():
    hub = FanoutHub()
    user_id = uuid.uuid4()
    hub.publish(user_id, "ping", {})
    hub.publish(user_id, "ping", {})

    hello = hub.build_hello(user_id)

    assert hello["type"] == "hello"
    assert hello["seq"] == 2
    assert hello["data"]["seq"] == 2
    assert hello["data"]["heartbeat_s"] == 30


def test_build_hello_for_a_never_seen_user_starts_at_zero():
    hub = FanoutHub()
    hello = hub.build_hello(uuid.uuid4())
    assert hello["seq"] == 0
    assert hello["data"]["seq"] == 0


def test_build_ping():
    hub = FanoutHub()
    user_id = uuid.uuid4()
    hub.publish(user_id, "glucose.reading", {})

    ping = hub.build_ping(user_id)
    assert ping["type"] == "ping"
    assert ping["seq"] == 1
    assert ping["data"] == {}
