import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/auth_storage_service.dart';
import '../../../core/api/api_client.dart';

enum AuthStatus { initial, unauthenticated, authenticated, onboardingRequired }

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  
  AuthState({required this.status, this.errorMessage});
}

class AuthNotifier extends AutoDisposeAsyncNotifier<AuthState> {
  final _storage = AuthStorageService();
  
  @override
  Future<AuthState> build() async {
    return _checkAuthStatus();
  }
  
  Future<AuthState> _checkAuthStatus() async {
    final token = await _storage.getAccessToken();
    final hasCompletedOnboarding = await _storage.hasCompletedOnboarding();
    
    if (token == null) {
      if (!hasCompletedOnboarding) {
        return AuthState(status: AuthStatus.onboardingRequired);
      }
      return AuthState(status: AuthStatus.unauthenticated);
    }
    
    // Validate token with backend
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.get('/auth/me');
      return AuthState(status: AuthStatus.authenticated);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        // Token expired — try refresh
        final refreshSuccess = await refreshSession();
        if (refreshSuccess) {
          return AuthState(status: AuthStatus.authenticated);
        }
        return AuthState(status: AuthStatus.unauthenticated);
      }
      // Network error — assume authenticated if token exists
      return AuthState(status: AuthStatus.authenticated);
    }
  }
  
  Future<bool> refreshSession() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) return false;
    
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post('/auth/refresh', data: {'refresh_token': refreshToken});
      await _storage.saveTokens(
        access: response.data['access_token'],
        refresh: response.data['refresh_token'],
      );
      return true;
    } catch (e) {
      await logout();
      return false;
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      
      await _storage.saveTokens(
        access: response.data['access_token'],
        refresh: response.data['refresh_token'],
      );
      
      // Since they already have an account, mark onboarding as complete
      await _storage.setOnboardingCompleted();
      
      state = AsyncData(AuthState(status: AuthStatus.authenticated));
    } catch (e) {
      state = AsyncData(AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString(),
      ));
      rethrow;
    }
  }
  
  Future<void> logout() async {
    await _storage.clearAll();
    state = AsyncData(AuthState(status: AuthStatus.unauthenticated));
  }
  
  Future<void> completeOnboarding(String accessToken, String refreshToken) async {
    await _storage.saveTokens(access: accessToken, refresh: refreshToken);
    await _storage.setOnboardingCompleted();
    state = AsyncData(AuthState(status: AuthStatus.authenticated));
  }
}

final authProvider = AsyncNotifierProvider.autoDispose<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
