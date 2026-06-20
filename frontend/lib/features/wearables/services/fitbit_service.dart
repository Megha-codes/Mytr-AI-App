import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

class FitbitActivityData {
  final int steps;
  final int caloriesOut;
  final int activeMinutes;

  const FitbitActivityData({
    required this.steps,
    required this.caloriesOut,
    required this.activeMinutes,
  });
}

class FitbitService {
  FitbitService._();
  static final FitbitService instance = FitbitService._();

  static const _clientId = String.fromEnvironment(
    'FITBIT_CLIENT_ID',
    defaultValue: '',
  );
  static const _redirectUri = 'mytrai://fitbit-callback';
  static const _scopes = 'activity heartrate sleep';

  static const _accessTokenKey = 'fitbit_access_token';
  static const _refreshTokenKey = 'fitbit_refresh_token';
  static const _expiryKey = 'fitbit_token_expiry';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final _dio = Dio(BaseOptions(
    baseUrl: 'https://api.fitbit.com',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  bool get isConfigured => _clientId.isNotEmpty;

  Future<bool> isConnected() async {
    final token = await _storage.read(key: _accessTokenKey);
    return token != null;
  }

  Future<void> connect() async {
    if (!isConfigured) {
      throw Exception(
        'FITBIT_CLIENT_ID is not set. Add it to your .env and rebuild with '
        '--dart-define=FITBIT_CLIENT_ID=<your_id>',
      );
    }

    final verifier = _generateVerifier();
    final challenge = _generateChallenge(verifier);

    final authUrl = Uri.https('www.fitbit.com', '/oauth2/authorize', {
      'response_type': 'code',
      'client_id': _clientId,
      'redirect_uri': _redirectUri,
      'scope': _scopes,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    }).toString();

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl,
      callbackUrlScheme: 'mytrai',
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

  Future<FitbitActivityData> fetchToday() async {
    final token = await _getValidToken();
    final response = await _dio.get(
      '/1/user/-/activities/date/today.json',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final summary = response.data['summary'] as Map<String, dynamic>;
    return FitbitActivityData(
      steps: (summary['steps'] as num?)?.toInt() ?? 0,
      caloriesOut: (summary['caloriesOut'] as num?)?.toInt() ?? 0,
      activeMinutes: ((summary['fairlyActiveMinutes'] as num?)?.toInt() ?? 0) +
          ((summary['veryActiveMinutes'] as num?)?.toInt() ?? 0),
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _exchangeCode(String code, String verifier) async {
    final response = await _dio.post(
      '/oauth2/token',
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

  Future<void> _refreshTokens(String refresh) async {
    final response = await _dio.post(
      '/oauth2/token',
      data: {
        'grant_type': 'refresh_token',
        'client_id': _clientId,
        'refresh_token': refresh,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    await _storeTokens(response.data as Map<String, dynamic>);
  }

  Future<void> _storeTokens(Map<String, dynamic> data) async {
    final access = data['access_token'] as String;
    final refresh = data['refresh_token'] as String;
    final expiresIn = (data['expires_in'] as num).toInt();
    final expiry = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .toIso8601String();

    await Future.wait([
      _storage.write(key: _accessTokenKey, value: access),
      _storage.write(key: _refreshTokenKey, value: refresh),
      _storage.write(key: _expiryKey, value: expiry),
    ]);
  }

  Future<String> _getValidToken() async {
    final expStr = await _storage.read(key: _expiryKey);
    if (expStr != null) {
      final expiry = DateTime.parse(expStr);
      if (DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 5)))) {
        final refresh = await _storage.read(key: _refreshTokenKey);
        if (refresh != null) await _refreshTokens(refresh);
      }
    }
    final token = await _storage.read(key: _accessTokenKey);
    if (token == null) throw Exception('Not connected to Fitbit');
    return token;
  }

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
