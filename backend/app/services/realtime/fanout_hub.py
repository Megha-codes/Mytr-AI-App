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
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import select

from ...models.glucose_reading import GlucoseReadingModel
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

# Resume replays from the store, bounded to this window (§2.6) — a link that
# was down longer than this re-syncs from /snapshot instead of replaying.
RESUME_WINDOW = timedelta(hours=24)


class ResumeResult:
    """Either a (possibly empty) batch of glucose.reading frames to replay,
    or a signal that the hub can't reconcile `since_seq` and the client
    should resync (§2.6: `{"type": "resync"}`) instead."""

    __slots__ = ("envelopes", "resync")

    def __init__(self, envelopes: Optional[list[dict]] = None, resync: bool = False) -> None:
        self.envelopes = envelopes or []
        self.resync = resync


class FanoutHub:
    def __init__(self) -> None:
        self._subscribers: dict[str, set[asyncio.Queue]] = defaultdict(set)
        self._seq: dict[str, int] = defaultdict(int)
        # seq -> recorded_at of the glucose.reading published at that seq,
        # per user. The only bookkeeping resume() needs to translate a
        # client's since_seq into a "replay everything after this instant"
        # store query. Pruned to RESUME_WINDOW so a long-lived process
        # doesn't accumulate this forever.
        self._reading_checkpoints: dict[str, dict[int, datetime]] = defaultdict(dict)

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

    def publish(
        self, user_id, type_: str, data: dict, *, checkpoint_at: Optional[datetime] = None
    ) -> dict:
        """Builds the envelope (assigning the next seq for this user) and
        delivers it to every live subscriber for that user_id. A user_id
        with no subscribers still gets its seq counter advanced — the
        counter tracks the stream, not who's listening.

        `checkpoint_at` records this seq's timestamp for resume() to later
        translate a since_seq back into a store query — only
        publish_glucose_reading() needs this; other frame types don't
        participate in replay.
        """
        key = str(user_id)
        self._seq[key] += 1
        seq = self._seq[key]
        envelope = build_envelope(type_, seq, data)

        if checkpoint_at is not None:
            self._record_checkpoint(key, seq, checkpoint_at)

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
        return self.publish(user_id, FRAME_TYPE_GLUCOSE_READING, data, checkpoint_at=recorded_at)

    def publish_glucose_state(self, user_id, *, state: str, since: datetime) -> dict:
        data = build_glucose_state_data(state, since)
        return self.publish(user_id, FRAME_TYPE_GLUCOSE_STATE, data)

    # ── Connection-lifecycle frames (built on demand, not "published") ──────

    def build_hello(self, user_id) -> dict:
        seq = self.current_seq(user_id)
        return build_envelope(FRAME_TYPE_HELLO, seq, build_hello_data(seq))

    def build_ping(self, user_id) -> dict:
        return build_envelope(FRAME_TYPE_PING, self.current_seq(user_id), {})

    # ── Resume-on-reconnect (§2.6) ───────────────────────────────────────────

    async def resume(self, user_id, since_seq: int, session_factory) -> ResumeResult:
        """A flaky-link recovery path: the client's first frame after
        reconnecting is `{"type":"resume","since_seq":N}`. Replays
        glucose.reading frames the client missed, sourced from the
        glucose_readings store (not an in-memory log — the store is already
        the durable, deduplicated record of what was actually ingested).

        since_seq==0 means "I have nothing yet", so hand back the whole
        RESUME_WINDOW. Any other since_seq must map to a checkpoint this hub
        recorded itself (via publish_glucose_reading) — an unrecognized one
        (too old and pruned, or from a hub lifetime before a restart, since
        the seq counter is in-process only) can't be reconciled, so the
        caller should resync from /snapshot instead.

        Replayed frames all carry the *current* seq, not reconstructed
        original ones — the store doesn't persist per-reading seq numbers,
        and the property that matters here is that the client ends up
        caught up with the right data in the right order, not exact seq
        fidelity on historical frames.
        """
        key = str(user_id)
        current = self._seq.get(key, 0)

        if since_seq < 0 or since_seq > current:
            return ResumeResult(resync=True)
        if since_seq == current:
            return ResumeResult(envelopes=[])

        now = datetime.now(timezone.utc)
        if since_seq == 0:
            since = now - RESUME_WINDOW
        else:
            checkpoint = self._reading_checkpoints.get(key, {}).get(since_seq)
            if checkpoint is None:
                return ResumeResult(resync=True)
            since = max(checkpoint, now - RESUME_WINDOW)

        async with session_factory() as db:
            result = await db.execute(
                select(GlucoseReadingModel)
                .where(GlucoseReadingModel.user_id == user_id, GlucoseReadingModel.recorded_at > since)
                .order_by(GlucoseReadingModel.recorded_at.asc())
            )
            readings = result.scalars().all()

        envelopes = [
            build_envelope(
                FRAME_TYPE_GLUCOSE_READING,
                current,
                build_glucose_reading_data(
                    ts=reading.recorded_at,
                    mgdl=reading.value_mgdl,
                    trend=reading.trend,
                    trend_arrow=reading.trend_arrow,
                    sensor_id=reading.sensor_id,
                    source=reading.source,
                ),
            )
            for reading in readings
        ]
        return ResumeResult(envelopes=envelopes)

    # ── Internals ────────────────────────────────────────────────────────────

    def _record_checkpoint(self, user_id: str, seq: int, recorded_at: datetime) -> None:
        checkpoints = self._reading_checkpoints[user_id]
        checkpoints[seq] = recorded_at
        cutoff = datetime.now(timezone.utc) - RESUME_WINDOW
        for stale_seq in [s for s, ts in checkpoints.items() if ts < cutoff]:
            del checkpoints[stale_seq]


# Module-level singleton — the app-wide fanout hub. LibreIngestionService and
# POST /glucose/manual both publish through this instance by default.
fanout_hub = FanoutHub()
