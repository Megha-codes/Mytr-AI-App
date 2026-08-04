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

    # Which SecretsStore backs the app-wide secrets_manager singleton
    # (architecture-v3.md §4.3 step 7): "memory" (MockSecretsManager, dev/test
    # default — not durable) or "kms_postgres" (KmsPostgresSecretsStore).
    SECRETS_STORE_BACKEND: str = os.getenv("SECRETS_STORE_BACKEND", "memory")

    # Which KmsClient backs envelope encryption for KmsPostgresSecretsStore:
    # "local" (LocalKmsClient, dev/test default) or "aws" (AwsKmsClient).
    KMS_BACKEND: str = os.getenv("KMS_BACKEND", "local")
    # AWS KMS customer master key id/ARN. Required when KMS_BACKEND=aws.
    AWS_KMS_KEY_ID: str = os.getenv("AWS_KMS_KEY_ID", "")
    # Base64 Fernet key backing LocalKmsClient's simulated master key. Must be
    # stable across restarts (generate once with
    # `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`)
    # or every previously-wrapped data key becomes permanently unreadable —
    # same durability requirement as encryption.py's ENCRYPTION_KEY. Empty ->
    # a fresh key is generated per process (fine for dev, breaks durability).
    LOCAL_KMS_MASTER_KEY: str = os.getenv("LOCAL_KMS_MASTER_KEY", "")


settings = Settings()
