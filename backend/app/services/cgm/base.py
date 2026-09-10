"""Shared base types for every CGM service (Libre, manual entry, Accu-Chek).

Deliberately its own module with zero dependency on any concrete service or
on factory.py: every concrete service needs these types, and factory.py
needs to import the concrete services to build its device_type -> service
map. If the base types lived in factory.py instead (as they used to), any
concrete service module — which all import these types — would trigger
factory.py's own module-level import of every concrete service the moment
it was imported *first*, which circles straight back into the concrete
module still being initialized. That was exactly the bug: `libre_service.py`
imported `BaseCGMService`/`CGMReading` from `.factory`, and `factory.py`
imported `LibreCGMService` from `.libre_service` — whichever of the two
Python happened to import first would fail with an ImportError on the
partially-initialized other module. See factory.py's own comment, and
tests/test_libre_service.py's subprocess regression test.
"""

from datetime import datetime
from dataclasses import dataclass


@dataclass
class CGMReading:
    value: int
    timestamp: datetime
    trend: str
    trend_arrow: str = "→"
    device_type: str = "UNKNOWN"
    is_continuous: bool = True


class BaseCGMService:
    is_continuous: bool = False
    supports_trend: bool = False

    async def get_latest_reading(self, user_id: str) -> CGMReading | None:
        raise NotImplementedError()

    async def get_reading_at_time(
        self, user_id: str, target_time: datetime, tolerance_minutes: int = 10
    ) -> CGMReading | None:
        raise NotImplementedError()
