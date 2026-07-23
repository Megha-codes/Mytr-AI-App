"""In-process fan-out hub backing the /v1/devices/stream delivery guarantee.

A single process runs both the Libre poller and the WebSocket stream endpoint.
When a device's stream connection is accepted it ``subscribe()``s *before*
doing anything else; from that instant every reading the poller ``publish()``es
lands in that subscriber's queue. That is exactly the contract syncd depends
on: "once a device's connection is accepted, deliver everything published from
that point on" — so its stream-first-then-backfill ordering can't drop a
reading in the gap between connecting and issuing its backfill request.
"""

from __future__ import annotations

import asyncio
import logging

logger = logging.getLogger("mytr.device_hub")


class DeviceStreamHub:
    def __init__(self) -> None:
        self._subscribers: set[asyncio.Queue] = set()

    def subscribe(self) -> asyncio.Queue:
        """Register a new subscriber. Everything published after this call is
        delivered to the returned queue, in order."""
        queue: asyncio.Queue = asyncio.Queue()
        self._subscribers.add(queue)
        logger.debug("stream subscriber added (now %d)", len(self._subscribers))
        return queue

    def unsubscribe(self, queue: asyncio.Queue) -> None:
        self._subscribers.discard(queue)
        logger.debug("stream subscriber removed (now %d)", len(self._subscribers))

    async def publish(self, reading: dict) -> None:
        """Fan a reading out to every current subscriber."""
        for queue in list(self._subscribers):
            await queue.put(reading)

    @property
    def subscriber_count(self) -> int:
        return len(self._subscribers)


# Module-level singleton shared by the poller (publisher) and the stream route
# (subscribers), which run in the same process.
hub = DeviceStreamHub()
