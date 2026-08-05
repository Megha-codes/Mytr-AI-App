class AppConfig {
  AppConfig._();

  // ── API base URL ──────────────────────────────────────────────────────────
  /// HTTP base URL for the FastAPI backend, including the `/api/v1` version
  /// prefix. Every REST router is mounted under `/api/v1`, so all call sites
  /// use prefix-less paths (e.g. `/auth/login`, `/dashboard`) and the prefix
  /// lives here exactly once.
  ///
  /// This is the single source of truth for the network layer (see
  /// [Environment] for the dotenv-based defaults — they are kept in sync).
  /// Override at build time with:
  ///   --dart-define=API_BASE_URL=https://api.mytr.ai/api/v1
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1', // Android emulator localhost
  );

  // ── WebSocket base URL ────────────────────────────────────────────────────
  /// Server origin with a ws/wss scheme. WebSocket routes are mounted at the
  /// server root (`/ws/...`), NOT under `/api/v1`, so the version prefix is
  /// stripped here. Call sites append the concrete path, e.g.
  /// `'$wsBaseUrl/ws/app/stream'`.
  static String get wsBaseUrl {
    final origin = apiBaseUrl.replaceFirst(RegExp(r'/api/v\d+/?$'), '');
    return origin
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
  }

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
