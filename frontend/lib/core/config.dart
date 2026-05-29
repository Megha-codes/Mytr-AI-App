class AppConfig {
  AppConfig._();

  // ── API base URL ──────────────────────────────────────────────────────────
  /// HTTP base URL for the FastAPI backend.
  /// Override at build time with: --dart-define=API_BASE_URL=https://api.mytr.ai
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000', // Android emulator localhost
  );

  // ── WebSocket base URL ────────────────────────────────────────────────────
  /// Derived automatically from apiBaseUrl by swapping the scheme.
  /// e.g. http://... → ws://..., https://... → wss://...
  static String get wsBaseUrl {
    return apiBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
  }

  // ── Dexcom OAuth ──────────────────────────────────────────────────────────
  /// Dexcom developer client ID.
  /// Override at build time with: --dart-define=DEXCOM_CLIENT_ID=abc123
  static const dexcomClientId = String.fromEnvironment(
    'DEXCOM_CLIENT_ID',
    defaultValue: '',
  );

  /// Dexcom sandbox vs production host.
  /// Override at build time with: --dart-define=DEXCOM_HOST=api.dexcom.com
  static const dexcomApiHost = String.fromEnvironment(
    'DEXCOM_HOST',
    defaultValue: 'sandbox-api.dexcom.com', // sandbox for development
  );

  /// Path for the Dexcom OAuth login endpoint.
  static const dexcomOAuthPath = '/v2/oauth2/login';

  /// The custom URL scheme registered in AndroidManifest / Info.plist.
  /// Must match the scheme in dexcomRedirectUri.
  static const dexcomCallbackScheme = 'mytrai';

  /// Full redirect URI passed to Dexcom OAuth.
  static const dexcomRedirectUri = '$dexcomCallbackScheme://dexcom/callback';

  // ── FreeStyle Libre ───────────────────────────────────────────────────────
  /// LibreLinkUp API region.
  /// Possible values: 'AE', 'AP', 'AU', 'CA', 'DE', 'EU', 'EU2', 'FR', 
  ///                  'JP', 'US', 'LA', 'RU'
  /// Override at build time with: --dart-define=LIBRE_REGION=EU
  /// Defaults to 'AP' (Asia-Pacific) for India.
  static const libreRegion = String.fromEnvironment(
    'LIBRE_REGION',
    defaultValue: 'AP',
  );
}
