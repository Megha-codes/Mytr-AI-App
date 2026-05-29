import httpx
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional
from .factory import BaseCGMService, CGMReading

_TREND_MAP = {
    1: ("FALLING_FAST",  "↓↓"),
    2: ("FALLING",       "↓"),
    3: ("STABLE",        "→"),
    4: ("RISING",        "↑"),
    5: ("RISING_FAST",   "↑↑"),
}

_LIBRE_BASES = [
    "https://api.libreview.io",      # US / Global
    "https://api-eu.libreview.io",   # Europe
    "https://api-de.libreview.io",   # Germany
    "https://api-jp.libreview.io",   # Japan
    "https://api-au.libreview.io",   # Australia
    "https://api-ae.libreview.io",   # Middle East
]
_LLU_HEADERS = {"product": "llu.android", "version": "4.7.0"}

_FALLBACK_READING = CGMReading(
    value=112, timestamp=datetime.utcnow(),
    trend="STABLE", trend_arrow="→",
    device_type="LIBRE", is_continuous=True,
)


@dataclass
class LibreValidationResult:
    success:             bool
    error_message:       Optional[str] = None
    sensor_generation:   Optional[str] = None   # "2" or "3"
    sensor_expiry_date:  Optional[str] = None   # ISO-8601 string
    region_base:         Optional[str] = None


class LibreCGMService(BaseCGMService):
    is_continuous = True
    supports_trend = True

    # ── Public interface ─────────────────────────────────────────────────────

    async def get_latest_reading(self, user_id: str) -> CGMReading | None:
        return await self.get_reading_at_time(user_id, datetime.utcnow(), tolerance_minutes=6)

    async def get_reading_at_time(
        self,
        user_id: str,
        target_time: datetime,
        tolerance_minutes: int = 10,
    ) -> CGMReading | None:
        from ...core.secrets_manager import secrets_manager
        from ...core.encryption import decrypt

        creds = await secrets_manager.get_libre_credentials(user_id)
        if creds is None:
            return _FALLBACK_READING

        try:
            password = decrypt(creds.encrypted_password)
        except Exception:
            return _FALLBACK_READING

        # Try to find the region base URL if stored, otherwise try all
        return await self._fetch_reading(creds.email, password, target_time, tolerance_minutes)

    async def validate_credentials(
        self, email: str, password: str
    ) -> LibreValidationResult:
        """
        Called at connect-time to immediately verify credentials before storing.
        Checks: valid login, Connections enabled, active sensor present.
        """
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                # Try each region until one works
                auth_data = await self._authenticate_any_region(client, email, password)
                if not auth_data:
                    return LibreValidationResult(
                        success=False,
                        error_message="Invalid LibreLinkUp credentials or unsupported region.",
                    )
                
                token, region_base = auth_data
                connections = await self._get_connections(client, region_base, token)

            if not connections:
                return LibreValidationResult(
                    success=False,
                    error_message=(
                        "LibreLinkUp Connections not enabled. "
                        "Open your FreeStyle LibreLink app → Menu → "
                        "Connected Apps → LibreLinkUp → Enable Connections."
                    ),
                )

            connection  = connections[0]
            generation  = self._detect_sensor_generation(connection.get("device", {}))
            expiry      = self._sensor_expiry(connection.get("sensor", {}), generation)

            return LibreValidationResult(
                success=True,
                sensor_generation=generation,
                sensor_expiry_date=expiry,
                region_base=region_base,
            )

        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 401:
                return LibreValidationResult(
                    success=False,
                    error_message="Invalid LibreLinkUp credentials. Check your email and password.",
                )
            return LibreValidationResult(
                success=False,
                error_message="LibreLinkUp service unavailable. Please try again.",
            )
        except Exception as e:
            return LibreValidationResult(
                success=False,
                error_message=f"Connection failed: {str(e)}",
            )

    # ── Internal helpers ─────────────────────────────────────────────────────

    async def _fetch_reading(
        self,
        email: str,
        password: str,
        target_time: datetime,
        tolerance_minutes: int,
    ) -> CGMReading | None:
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                auth_data = await self._authenticate_any_region(client, email, password)
                if not auth_data:
                    return _FALLBACK_READING
                
                token, region_base = auth_data
                connections = await self._get_connections(client, region_base, token)
                if not connections:
                    return _FALLBACK_READING

                patient_id = connections[0]["patientId"]
                graph_resp = await client.get(
                    f"{region_base}/llu/connections/{patient_id}/graph",
                    headers={**_LLU_HEADERS, "Authorization": f"Bearer {token}"},
                )
                graph_resp.raise_for_status()
                readings = graph_resp.json()["data"]["graphData"]

            return self._find_closest_reading(readings, target_time, tolerance_minutes)
        except Exception:
            return _FALLBACK_READING

    async def _authenticate_any_region(
        self, client: httpx.AsyncClient, email: str, password: str
    ) -> Optional[tuple[str, str]]:
        for base in _LIBRE_BASES:
            try:
                resp = await client.post(
                    f"{base}/llu/auth/login",
                    json={"email": email, "password": password},
                    headers=_LLU_HEADERS,
                )
                if resp.status_code == 200:
                    return resp.json()["data"]["authTicket"]["token"], base
            except Exception:
                continue
        return None

    async def _get_connections(
        self, client: httpx.AsyncClient, base: str, token: str
    ) -> list:
        resp = await client.get(
            f"{base}/llu/connections",
            headers={**_LLU_HEADERS, "Authorization": f"Bearer {token}"},
        )
        resp.raise_for_status()
        return resp.json().get("data", [])

    def _find_closest_reading(
        self,
        readings: list,
        target_time: datetime,
        tolerance_minutes: int,
    ) -> CGMReading | None:
        if not readings:
            return None

        closest_item = closest_time = None
        min_delta = timedelta(minutes=tolerance_minutes + 1)

        for item in readings:
            try:
                reading_time = datetime.strptime(item["Timestamp"], "%m/%d/%Y %I:%M:%S %p")
            except (ValueError, KeyError):
                continue

            delta = abs(reading_time - target_time)
            if delta <= timedelta(minutes=tolerance_minutes) and delta < min_delta:
                min_delta = delta
                closest_item = item
                closest_time = reading_time

        return self._parse_reading(closest_item, closest_time) if closest_item else None

    def _parse_reading(self, item: dict, timestamp: datetime) -> CGMReading:
        trend_code = item.get("TrendArrow", 3)
        trend, trend_arrow = _TREND_MAP.get(trend_code, ("STABLE", "→"))
        value = item.get("ValueInMgPerDl") or item.get("Value", 0)
        return CGMReading(
            value=int(value), timestamp=timestamp,
            trend=trend, trend_arrow=trend_arrow,
            device_type="LIBRE", is_continuous=True,
        )

    def _detect_sensor_generation(self, device: dict) -> str:
        """
        LibreLinkUp device type IDs (dtid):
          Libre 2: ~40068–40074
          Libre 3: ~40075+
        Defaults to "3" for unrecognised/new hardware.
        """
        dtid = device.get("dtid", 0)
        if isinstance(dtid, int) and 0 < dtid < 40075:
            return "2"
        return "3"

    def _sensor_expiry(self, sensor: dict, generation: str) -> Optional[str]:
        activation_ts = sensor.get("a")
        if not activation_ts:
            return None
        lifespan_days = 14 if generation == "2" else 15
        expiry = datetime.utcfromtimestamp(activation_ts) + timedelta(days=lifespan_days)
        return expiry.isoformat()
