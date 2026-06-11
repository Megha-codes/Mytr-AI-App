import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  static const _accessTokenKey        = 'access_token';
  static const _refreshTokenKey       = 'refresh_token';
  static const _onboardingCompletedKey = 'has_completed_onboarding';
  static const _userTypeKey           = 'user_type';
  static const _onboardingStepKey     = 'onboarding_step';

  Future<void> saveTokens({required String access, required String refresh}) async {
    try {
      await _storage.write(key: _accessTokenKey, value: access);
      await _storage.write(key: _refreshTokenKey, value: refresh);
    } catch (_) {
      await _nukeAndRetry(() async {
        await _storage.write(key: _accessTokenKey, value: access);
        await _storage.write(key: _refreshTokenKey, value: refresh);
      });
    }
  }

  Future<String?> getAccessToken() => _safeRead(_accessTokenKey);
  Future<String?> getRefreshToken() => _safeRead(_refreshTokenKey);

  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }

  Future<bool> hasCompletedOnboarding() async {
    final val = await _safeRead(_onboardingCompletedKey);
    return val == 'true';
  }

  Future<void> setOnboardingCompleted() async {
    try {
      await _storage.write(key: _onboardingCompletedKey, value: 'true');
    } catch (_) {}
  }

  Future<void> saveUserType(String type) async {
    try {
      await _storage.write(key: _userTypeKey, value: type);
    } catch (_) {}
  }

  Future<String?> getUserType() => _safeRead(_userTypeKey);

  Future<void> saveOnboardingStep(int step) async {
    try {
      await _storage.write(key: _onboardingStepKey, value: step.toString());
    } catch (_) {}
  }

  Future<int?> getOnboardingStep() async {
    final val = await _safeRead(_onboardingStepKey);
    return val != null ? int.tryParse(val) : null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // Corrupted Keystore entry — wipe all and return null
      try { await _storage.deleteAll(); } catch (_) {}
      return null;
    }
  }

  Future<void> _nukeAndRetry(Future<void> Function() action) async {
    try {
      await _storage.deleteAll();
      await action();
    } catch (_) {}
  }
}
