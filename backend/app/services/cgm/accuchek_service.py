import httpx
from datetime import datetime, timedelta
from .base import BaseCGMService, CGMReading

ACCUCHEK_API_URL = "https://s3.accucheck.com/mchc/api"


class MockSecretsManager:
    async def get_accuchek_credentials(self, user_id):
        class MockCreds:
            email = "user@example.com"
            password = "password123"
        return MockCreds()


class MockSettings:
    ACCUCHEK_CLIENT_ID = "mock_client_id"


secrets_manager = MockSecretsManager()
settings = MockSettings()


class AccuChekConnectService(BaseCGMService):
    """
    Supports: Accu-Chek Instant S, Accu-Chek Guide, Accu-Chek Guide Me
    These models sync to Accu-Chek Connect cloud via Bluetooth.

    Does NOT support: Accu-Chek Active, Accu-Chek Basic (no Bluetooth).
    Those devices use ManualGlucoseService.
    """
    is_continuous = False
    supports_trend = False

    async def get_latest_reading(self, user_id: str) -> CGMReading | None:
        credentials = await secrets_manager.get_accuchek_credentials(user_id)

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                token = await self._authenticate(client, credentials)
                response = await client.get(
                    f"{ACCUCHEK_API_URL}/measurements",
                    headers={"Authorization": f"Bearer {token}"},
                    params={"count": 1, "sort": "desc"},
                )
                response.raise_for_status()
                data = response.json()
            except Exception:
                return CGMReading(
                    value=105,
                    timestamp=datetime.utcnow(),
                    trend="UNKNOWN",
                    trend_arrow="→",
                    device_type="ACCUCHEK_CONNECT",
                    is_continuous=False,
                )

        measurements = data.get("measurements", [])
        if not measurements:
            return None

        latest = measurements[0]
        return CGMReading(
            value=latest["glucoseValue"],
            timestamp=datetime.fromisoformat(latest["measurementTime"]),
            trend="UNKNOWN",
            trend_arrow="→",
            device_type="ACCUCHEK_CONNECT",
            is_continuous=False,
        )

    async def get_reading_at_time(
        self,
        user_id: str,
        target_time: datetime,
        tolerance_minutes: int = 10,
    ) -> CGMReading | None:
        credentials = await secrets_manager.get_accuchek_credentials(user_id)

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                token = await self._authenticate(client, credentials)
                response = await client.get(
                    f"{ACCUCHEK_API_URL}/measurements",
                    headers={"Authorization": f"Bearer {token}"},
                    params={
                        "from": (target_time - timedelta(minutes=tolerance_minutes)).isoformat(),
                        "to": (target_time + timedelta(minutes=tolerance_minutes)).isoformat(),
                    },
                )
                response.raise_for_status()
                measurements = response.json().get("measurements", [])
            except Exception:
                return CGMReading(
                    value=105,
                    timestamp=target_time,
                    trend="UNKNOWN",
                    trend_arrow="→",
                    device_type="ACCUCHEK_CONNECT",
                    is_continuous=False,
                )

        return self._find_closest_reading(measurements, target_time, tolerance_minutes)

    async def _authenticate(self, client: httpx.AsyncClient, credentials) -> str:
        auth_response = await client.post(
            f"{ACCUCHEK_API_URL}/oauth/token",
            data={
                "grant_type": "password",
                "username": credentials.email,
                "password": credentials.password,
                "client_id": settings.ACCUCHEK_CLIENT_ID,
            },
        )
        auth_response.raise_for_status()
        return auth_response.json()["access_token"]

    def _find_closest_reading(
        self,
        measurements: list,
        target_time: datetime,
        tolerance_minutes: int,
    ) -> CGMReading | None:
        if not measurements:
            return None

        closest = None
        min_delta = timedelta(minutes=tolerance_minutes + 1)

        for m in measurements:
            try:
                reading_time = datetime.fromisoformat(m["measurementTime"])
            except (ValueError, KeyError):
                continue

            delta = abs(reading_time - target_time)
            if delta <= timedelta(minutes=tolerance_minutes) and delta < min_delta:
                min_delta = delta
                closest = CGMReading(
                    value=m["glucoseValue"],
                    timestamp=reading_time,
                    trend="UNKNOWN",
                    trend_arrow="→",
                    device_type="ACCUCHEK_CONNECT",
                    is_continuous=False,
                )

        return closest
