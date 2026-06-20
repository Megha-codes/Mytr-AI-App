import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

class GoogleHealthActivityData {
  final int steps;
  final int caloriesOut;
  final int heartRate;

  const GoogleHealthActivityData({
    required this.steps,
    required this.caloriesOut,
    required this.heartRate,
  });
}

class GoogleHealthService {
  GoogleHealthService._();
  static final GoogleHealthService instance = GoogleHealthService._();

  // Android OAuth 2.0 Client ID from Google Cloud Console.
  // Pass at build time: --dart-define=GOOGLE_HEALTH_CLIENT_ID=...
  static const _clientId = String.fromEnvironment(
    'GOOGLE_HEALTH_CLIENT_ID',
    defaultValue:
        '34668407605-ost28jkbt6b89cpokee4uqhbcl0oriik.apps.googleusercontent.com',
  );

  // Reverse-DNS redirect scheme required by Google for Android OAuth clients.
  static String get _redirectScheme {
    final base = _clientId.replaceAll('.apps.googleusercontent.com', '');
    return 'com.googleusercontent.apps.$base';
  }

  static String get _redirectUri => '$_redirectScheme:/oauth2redirect';

  // Scopes for steps + calories (activity_and_fitness) and heart rate
  // (health_metrics_and_measurements).
  static const _scopes = [
    'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
    'https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly',
  ];

  static const _accessTokenKey = 'google_health_access_token';
  static const _refreshTokenKey = 'google_health_refresh_token';
  static const _expiryKey = 'google_health_token_expiry';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final _authDio = Dio(BaseOptions(
    baseUrl: 'https://oauth2.googleapis.com',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  final _apiDio = Dio(BaseOptions(
    baseUrl: 'https://health.googleapis.com',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  Future<bool> isConnected() async {
    final token = await _storage.read(key: _accessTokenKey);
    return token != null;
  }

  Future<void> connect() async {
    final verifier = _generateVerifier();
    final challenge = _generateChallenge(verifier);

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'response_type': 'code',
      'client_id': _clientId,
      'redirect_uri': _redirectUri,
      'scope': _scopes.join(' '),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent', // always show consent to get refresh token
    }).toString();

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl,
      callbackUrlScheme: _redirectScheme,
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) throw Exception('Authorization cancelled or failed');

    await _exchangeCode(code, verifier);
  }

  Future<void> disconnect() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _expiryKey),
    ]);
  }

  Future<GoogleHealthActivityData> fetchToday() async {
    final token = await _getValidToken();
    final headers = {'Authorization': 'Bearer $token'};

    final now = DateTime.now();
    final today = _dateStr(now);
    final tomorrow = _dateStr(now.add(const Duration(days: 1)));

    int steps = 0;
    int calories = 0;
    int heartRate = 0;

    // Steps
    try {
      final resp = await _apiDio.get(
        '/v4/users/me/dataTypes/steps/dataPoints',
        queryParameters: {
          'filter':
              'steps.interval.civil_start_time >= "$today" AND steps.interval.civil_start_time < "$tomorrow"',
        },
        options: Options(headers: headers),
      );
      final points = (resp.data['dataPoints'] as List?) ?? [];
      steps = points.fold<int>(0, (sum, p) {
        final count = (p['steps']?['count'] as num?)?.toInt() ?? 0;
        return sum + count;
      });
    } catch (_) {}

    // Active calories burned
    try {
      final resp = await _apiDio.get(
        '/v4/users/me/dataTypes/active-energy-burned/dataPoints',
        queryParameters: {
          'filter':
              'active_energy_burned.interval.civil_start_time >= "$today" AND active_energy_burned.interval.civil_start_time < "$tomorrow"',
        },
        options: Options(headers: headers),
      );
      final points = (resp.data['dataPoints'] as List?) ?? [];
      calories = points.fold<int>(0, (sum, p) {
        final kcal =
            (p['activeEnergyBurned']?['kilocalories'] as num?)?.toInt() ?? 0;
        return sum + kcal;
      });
    } catch (_) {}

    // Heart rate (latest sample today)
    try {
      final resp = await _apiDio.get(
        '/v4/users/me/dataTypes/heart-rate/dataPoints',
        queryParameters: {
          'filter':
              'heart_rate.time >= "${today}T00:00:00Z" AND heart_rate.time < "${tomorrow}T00:00:00Z"',
          'pageSize': 1,
        },
        options: Options(headers: headers),
      );
      final points = (resp.data['dataPoints'] as List?) ?? [];
      if (points.isNotEmpty) {
        heartRate =
            (points.last['heartRate']?['beatsPerMinute'] as num?)?.toInt() ??
                0;
      }
    } catch (_) {}

    return GoogleHealthActivityData(
      steps: steps,
      caloriesOut: calories,
      heartRate: heartRate,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _exchangeCode(String code, String verifier) async {
    final response = await _authDio.post(
      '/token',
      data: {
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': _redirectUri,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    await _storeTokens(response.data as Map<String, dynamic>);
  }

  Future<void> _refresh(String refreshToken) async {
    final response = await _authDio.post(
      '/token',
      data: {
        'grant_type': 'refresh_token',
        'client_id': _clientId,
        'refresh_token': refreshToken,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    await _storeTokens(response.data as Map<String, dynamic>);
  }

  Future<void> _storeTokens(Map<String, dynamic> data) async {
    final access = data['access_token'] as String;
    final refresh = data['refresh_token'] as String?;
    final expiresIn = (data['expires_in'] as num).toInt();
    final expiry = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .toIso8601String();

    await _storage.write(key: _accessTokenKey, value: access);
    if (refresh != null) {
      await _storage.write(key: _refreshTokenKey, value: refresh);
    }
    await _storage.write(key: _expiryKey, value: expiry);
  }

  Future<String> _getValidToken() async {
    final expStr = await _storage.read(key: _expiryKey);
    if (expStr != null) {
      final expiry = DateTime.parse(expStr);
      if (DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 5)))) {
        final refresh = await _storage.read(key: _refreshTokenKey);
        if (refresh != null) await _refresh(refresh);
      }
    }
    final token = await _storage.read(key: _accessTokenKey);
    if (token == null) throw Exception('Not connected to Google Health');
    return token;
  }

  String _dateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _generateVerifier() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _generateChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
}
