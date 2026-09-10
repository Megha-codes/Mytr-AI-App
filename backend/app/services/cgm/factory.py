from .base import BaseCGMService, CGMReading

# Safe now: base.py (BaseCGMService/CGMReading) has no dependency on any of
# the concrete service modules below, so importing them here can't loop back
# into a module that's still mid-initialization — see base.py's docstring
# for the shape of the bug this used to be.
from .libre_service import LibreCGMService
from .manual_service import ManualGlucoseService

__all__ = ["BaseCGMService", "CGMReading", "cgm_service_factory"]


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
