import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _onboardingCompletedKey = 'has_completed_onboarding';
  static const _userTypeKey = 'user_type';
  static const _onboardingStepKey = 'onboarding_step';
  
  Future<void> saveTokens({required String access, required String refresh}) async {
    await _storage.write(key: _accessTokenKey, value: access);
    await _storage.write(key: _refreshTokenKey, value: refresh);
  }
  
  Future<String?> getAccessToken() => _storage.read(key: _accessTokenKey);
  Future<String?> getRefreshToken() => _storage.read(key: _refreshTokenKey);
  
  Future<void> clearAll() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _userTypeKey);
    await _storage.delete(key: _onboardingStepKey);
  }
  
  Future<bool> hasCompletedOnboarding() async {
    final val = await _storage.read(key: _onboardingCompletedKey);
    return val == 'true';
  }
  
  Future<void> setOnboardingCompleted() async {
    await _storage.write(key: _onboardingCompletedKey, value: 'true');
  }

  Future<void> saveUserType(String type) async {
    await _storage.write(key: _userTypeKey, value: type);
  }

  Future<String?> getUserType() => _storage.read(key: _userTypeKey);

  Future<void> saveOnboardingStep(int step) async {
    await _storage.write(key: _onboardingStepKey, value: step.toString());
  }

  Future<int?> getOnboardingStep() async {
    final val = await _storage.read(key: _onboardingStepKey);
    return val != null ? int.tryParse(val) : null;
  }
}
