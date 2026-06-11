import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime (.env) configuration. NOTE: the live network layer reads
/// [AppConfig] (compile-time dart-defines), not this class. These defaults are
/// kept consistent with [AppConfig] so the two never contradict each other:
///   • apiBaseUrl includes the `/api/v1` prefix.
///   • wsBaseUrl is the server origin only (the `/ws/...` path is added by call
///     sites), so it must NOT include `/api/v1` or a trailing `/ws`.
class Environment {
  static String get fileName => '.env';

  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000/api/v1';
  static String get wsBaseUrl => dotenv.env['WS_BASE_URL'] ?? 'ws://localhost:8000';

  static Future<void> init() async {
    await dotenv.load(fileName: 'assets/$fileName');
  }
}
