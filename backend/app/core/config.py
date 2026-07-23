import os

# Load a local .env (gitignored) if present, so LIBRE_* / JWT_SECRET / DB URLs
# can be supplied without exporting them. No-op when python-dotenv isn't
# installed or no .env exists, so production (real env vars) is unaffected.
try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:  # pragma: no cover - dotenv is optional at runtime
    pass


def _get_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default


class Settings:
    # Gemini Vision API (food image recognition)
    GOOGLE_API_KEY: str = os.getenv("GOOGLE_API_KEY", "")

    # USDA FoodData Central API (nutrition lookup)
    # Defaults to DEMO_KEY which is rate-limited; provide a real key for production
    USDA_API_KEY: str = os.getenv("USDA_API_KEY", "DEMO_KEY")

    # Garmin OAuth 1.0a
    GARMIN_CONSUMER_KEY:    str = os.getenv("GARMIN_CONSUMER_KEY", "")
    GARMIN_CONSUMER_SECRET: str = os.getenv("GARMIN_CONSUMER_SECRET", "")
    GARMIN_REDIRECT_URI:    str = os.getenv("GARMIN_REDIRECT_URI", "mytrai://garmin/callback")

    # ── LibreLinkUp poller (mytr-desk device pipeline) ────────────────────────
    # Credentials for the LibreLinkUp account the backend polls server-side.
    # Filled from .env (gitignored) — never hardcode or log these.
    LIBRE_EMAIL:    str = os.getenv("LIBRE_EMAIL", "")
    LIBRE_PASSWORD: str = os.getenv("LIBRE_PASSWORD", "")
    # Regional API host to use: us | eu | de | fr | jp | ap | au | ca.
    # A wrong region makes login return a redirect naming the correct one.
    LIBRE_REGION:   str = os.getenv("LIBRE_REGION", "ap")
    # Optional full base URL override (e.g. a staging proxy). When set it wins
    # over LIBRE_REGION. Leave empty to use the regional host.
    LIBRE_BASE_URL: str = os.getenv("LIBRE_BASE_URL", "")
    # IANA timezone the account's naive Libre timestamps are in (e.g.
    # "Asia/Kolkata", "America/New_York"). Used only when a reading has no
    # UTC FactoryTimestamp to fall back on; unset means treat as UTC (logged).
    LIBRE_ACCOUNT_TIMEZONE: str = os.getenv("LIBRE_ACCOUNT_TIMEZONE", "")
    # Seconds between poll cycles. Libre sensors update roughly once a minute.
    LIBRE_POLL_INTERVAL_S: int = _get_int("LIBRE_POLL_INTERVAL_S", 60)
    # Enable the in-process poller on app startup. Off by default so importing
    # the app (tests, the mobile-only server) never starts hitting Abbott.
    LIBRE_POLLER_ENABLED: bool = os.getenv("LIBRE_POLLER_ENABLED", "false").lower() in (
        "1", "true", "yes", "on",
    )

    # ── Device pairing ────────────────────────────────────────────────────────
    # Minutes a QR pairing session stays valid before it must be reopened.
    PAIRING_SESSION_TTL_MIN: int = _get_int("PAIRING_SESSION_TTL_MIN", 10)


settings = Settings()
