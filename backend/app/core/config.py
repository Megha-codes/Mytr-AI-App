import os


class Settings:
    # Gemini Vision API (food image recognition)
    GOOGLE_API_KEY: str = os.getenv("GOOGLE_API_KEY", "")

    # USDA FoodData Central API (nutrition lookup)
    # Defaults to DEMO_KEY which is rate-limited; provide a real key for production
    USDA_API_KEY: str = os.getenv("USDA_API_KEY", "DEMO_KEY")

    DEXCOM_CLIENT_ID:     str = os.getenv("DEXCOM_CLIENT_ID", "")
    DEXCOM_CLIENT_SECRET: str = os.getenv("DEXCOM_CLIENT_SECRET", "")
    DEXCOM_REDIRECT_URI:  str = os.getenv("DEXCOM_REDIRECT_URI", "mytrai://dexcom/callback")

    # Garmin OAuth 1.0a
    GARMIN_CONSUMER_KEY:    str = os.getenv("GARMIN_CONSUMER_KEY", "")
    GARMIN_CONSUMER_SECRET: str = os.getenv("GARMIN_CONSUMER_SECRET", "")
    GARMIN_REDIRECT_URI:    str = os.getenv("GARMIN_REDIRECT_URI", "mytrai://garmin/callback")

    # Used by token refresh — Dexcom v2 OAuth endpoint
    DEXCOM_TOKEN_URL = "https://api.dexcom.com/v2/oauth2/token"
    # EGV (Estimated Glucose Values) endpoint — Dexcom API v3
    DEXCOM_EGV_URL   = "https://api.dexcom.com/v3/users/self/egvs"


settings = Settings()
