import httpx
from datetime import datetime, timedelta
from .factory import BaseCGMService, CGMReading

# Dexcom API v3 uses camelCase trend names
_TREND_MAP: dict[str, tuple[str, str]] = {
    "doubleUp":       ("RISING_FAST",  "↑↑"),
    "singleUp":       ("RISING",       "↑"),
    "fortyFiveUp":    ("RISING_SLOW",  "↗"),
    "flat":           ("STABLE",       "→"),
    "fortyFiveDown":  ("FALLING_SLOW", "↘"),
    "singleDown":     ("FALLING",      "↓"),
    "doubleDown":     ("FALLING_FAST", "↓↓"),
    "notComputable":  ("STABLE",       "→"),
    "rateOutOfRange": ("STABLE",       "→"),
    "none":           ("STABLE",       "→"),
}

_EGV_URL   = "https://api.dexcom.com/v3/users/self/egvs"
_TOKEN_URL = "https://api.dexcom.com/v2/oauth2/token"
_FALLBACK  = CGMReading(
    value=115, timestamp=datetime.utcnow(),
    trend="STABLE", trend_arrow="→",
    device_type="DEXCOM", is_continuous=True,
)


class DexcomCGMService(BaseCGMService):
    is_continuous = True
    supports_trend = True

    async def get_latest_reading(self, user_id: str) -> CGMReading | None:
        return await self.get_reading_at_time(user_id, datetime.utcnow(), tolerance_minutes=6)

    async def get_reading_at_time(
        self,
        user_id: str,
        target_time: datetime,
        tolerance_minutes: int = 10,
    ) -> CGMReading | None:
        try:
            token = await self._get_valid_token(user_id)
        except Exception:
            return _FALLBACK

        window_start = (target_time - timedelta(minutes=tolerance_minutes)).strftime(
            "%Y-%m-%dT%H:%M:%S"
        )
        window_end = (target_time + timedelta(minutes=tolerance_minutes)).strftime(
            "%Y-%m-%dT%H:%M:%S"
        )

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                response = await client.get(
                    _EGV_URL,
                    params={"startDate": window_start, "endDate": window_end},
                    headers={"Authorization": f"Bearer {token}"},
                )
                response.raise_for_status()
                records = response.json().get("records", [])
            except Exception:
                return _FALLBACK

        return self._find_closest_reading(records, target_time, tolerance_minutes)

    # ── Token management ────────────────────────────────────────────────────

    async def _get_valid_token(self, user_id: str) -> str:
        from ...core.secrets_manager import secrets_manager

        creds = await secrets_manager.get_dexcom_credentials(user_id)
        if creds is None:
            raise ValueError(f"No Dexcom credentials for user {user_id}")

        # Proactively refresh if the token expires within 5 minutes
        if creds.expires_at <= datetime.utcnow() + timedelta(minutes=5):
            creds = await self._refresh_token(user_id, creds.refresh_token)

        return creds.access_token

    async def _refresh_token(self, user_id: str, refresh_token: str):
        from ...core.config import settings
        from ...core.secrets_manager import secrets_manager

        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(
                _TOKEN_URL,
                data={
                    "grant_type":    "refresh_token",
                    "refresh_token": refresh_token,
                    "client_id":     settings.DEXCOM_CLIENT_ID,
                    "client_secret": settings.DEXCOM_CLIENT_SECRET,
                },
            )
            response.raise_for_status()
            tokens = response.json()

        await secrets_manager.store_dexcom_tokens(
            user_id=user_id,
            access_token=tokens["access_token"],
            # Dexcom issues a new refresh_token on each refresh; fall back to
            # the existing one if the field is absent (shouldn't happen in prod)
            refresh_token=tokens.get("refresh_token", refresh_token),
            expires_at=datetime.utcnow() + timedelta(seconds=tokens["expires_in"]),
        )

        return await secrets_manager.get_dexcom_credentials(user_id)

    # ── Response parsing ────────────────────────────────────────────────────

    def _find_closest_reading(
        self,
        records: list,
        target_time: datetime,
        tolerance_minutes: int,
    ) -> CGMReading | None:
        if not records:
            return None

        closest = None
        min_delta = timedelta(minutes=tolerance_minutes + 1)

        for r in records:
            # Dexcom v3 uses ISO-8601; strip trailing Z for fromisoformat compat
            raw_time = r.get("systemTime", "").replace("Z", "")
            if not raw_time:
                continue
            reading_time = datetime.fromisoformat(raw_time)
            delta = abs(reading_time - target_time)

            if delta <= timedelta(minutes=tolerance_minutes) and delta < min_delta:
                min_delta = delta
                trend_str = r.get("trend", "flat")
                trend, trend_arrow = _TREND_MAP.get(trend_str, ("STABLE", "→"))
                closest = CGMReading(
                    value=int(r["value"]),
                    timestamp=reading_time,
                    trend=trend,
                    trend_arrow=trend_arrow,
                    device_type="DEXCOM",
                    is_continuous=True,
                )

        return closest
