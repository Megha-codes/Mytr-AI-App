"""FanoutHub: in-process pub/sub keyed on user_id (architecture-v3.md §2.6).

Every future websocket connection (Phase B: `/ws/app/stream`,
`/ws/device/stream`) will be a subscriber; `LibreIngestionService` and
`POST /glucose/manual` are today's publishers. Subscribers are plain
`asyncio.Queue` objects — deliberately not tied to any transport, so this is
tested directly with no websocket involved at all.
"""

from __future__ import annotations

import asyncio
from collections import defaultdict
from datetime import datetime
from typing import Optional

from .envelope import (
    FRAME_TYPE_GLUCOSE_READING,
    FRAME_TYPE_GLUCOSE_STATE,
    FRAME_TYPE_HELLO,
    FRAME_TYPE_PING,
    build_envelope,
    build_glucose_reading_data,
    build_glucose_state_data,
    build_hello_data,
)


class FanoutHub:
    def __init__(self) -> None:
        self._subscribers: dict[str, set[asyncio.Queue]] = defaultdict(set)
        self._seq: dict[str, int] = defaultdict(int)

    # ── Subscription ─────────────────────────────────────────────────────────

    def subscribe(self, user_id) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue()
        self._subscribers[str(user_id)].add(queue)
        return queue

    def unsubscribe(self, user_id, queue: asyncio.Queue) -> None:
        key = str(user_id)
        subscribers = self._subscribers.get(key)
        if subscribers is None:
            return
        subscribers.discard(queue)
        if not subscribers:
            del self._subscribers[key]

    def subscriber_count(self, user_id) -> int:
        return len(self._subscribers.get(str(user_id), ()))

    def current_seq(self, user_id) -> int:
        return self._seq.get(str(user_id), 0)

    # ── Publish ──────────────────────────────────────────────────────────────

    def publish(self, user_id, type_: str, data: dict) -> dict:
        """Builds the envelope (assigning the next seq for this user) and
        delivers it to every live subscriber for that user_id. A user_id
        with no subscribers still gets its seq counter advanced — the
        counter tracks the stream, not who's listening."""
        key = str(user_id)
        self._seq[key] += 1
        envelope = build_envelope(type_, self._seq[key], data)

        for queue in list(self._subscribers.get(key, ())):
            queue.put_nowait(envelope)
        return envelope

    def publish_glucose_reading(
        self,
        user_id,
        *,
        recorded_at: datetime,
        mgdl: int,
        trend: Optional[str],
        trend_arrow: Optional[str],
        sensor_id: Optional[str],
        source: str,
    ) -> dict:
        data = build_glucose_reading_data(
            ts=recorded_at, mgdl=mgdl, trend=trend, trend_arrow=trend_arrow,
            sensor_id=sensor_id, source=source,
        )
        return self.publish(user_id, FRAME_TYPE_GLUCOSE_READING, data)

    def publish_glucose_state(self, user_id, *, state: str, since: datetime) -> dict:
        data = build_glucose_state_data(state, since)
        return self.publish(user_id, FRAME_TYPE_GLUCOSE_STATE, data)

    # ── Connection-lifecycle frames (built on demand, not "published") ──────

    def build_hello(self, user_id) -> dict:
        seq = self.current_seq(user_id)
        return build_envelope(FRAME_TYPE_HELLO, seq, build_hello_data(seq))

    def build_ping(self, user_id) -> dict:
        return build_envelope(FRAME_TYPE_PING, self.current_seq(user_id), {})


# Module-level singleton — the app-wide fanout hub. LibreIngestionService and
# POST /glucose/manual both publish through this instance by default.
fanout_hub = FanoutHub()
