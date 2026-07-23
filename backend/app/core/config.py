import os


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

    # IANA timezone the LibreLinkUp account's naive timestamps are expressed in
    # (e.g. "Asia/Kolkata"). Used to convert LibreLinkUp's timezone-less
    # timestamps to UTC in the CGM path. Empty -> timestamps are treated as UTC.
    LIBRE_ACCOUNT_TIMEZONE: str = os.getenv("LIBRE_ACCOUNT_TIMEZONE", "")


settings = Settings()
