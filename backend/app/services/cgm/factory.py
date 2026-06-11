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


from .libre_service import LibreCGMService
from .manual_service import ManualGlucoseService


def cgm_service_factory(device_type: str) -> BaseCGMService:
    services: dict[str, BaseCGMService] = {
        "LIBRE_2":   LibreCGMService(),
        "LIBRE_3":   LibreCGMService(),
        "MANUAL":    ManualGlucoseService(),
    }
    service = services.get(device_type)
    if not service:
        raise ValueError(f"Unsupported device type: {device_type}")
    return service
