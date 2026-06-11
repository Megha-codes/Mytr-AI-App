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
      // The ApiClient interceptor transparently refreshes the access token on a
      // 401 and retries. So if this still throws 401, the refresh token is also
      // dead — treat the session as unauthenticated.
      await apiClient.get('/auth/me');
      return AuthState(status: AuthStatus.authenticated);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await logout();
        return AuthState(status: AuthStatus.unauthenticated);
      }
      // Network error — assume authenticated if a token exists; the next
      // authenticated request will re-validate.
      return AuthState(status: AuthStatus.authenticated);
    }
  }

  Future<void> login(String email, String password, {bool rememberMe = false}) async {
    state = const AsyncLoading();
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post('/auth/login', data: {
        'email': email,
        'password': password,
        'remember_me': rememberMe,
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

  /// Requests a password-reset email. Does not alter auth state. The backend
  /// intentionally returns success even when the email is unknown, so callers
  /// should show a neutral "if an account exists…" confirmation.
  Future<void> requestPasswordReset(String email) async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.post('/auth/forgot-password', data: {'email': email});
  }

  /// Completes a password reset using the token from the reset link.
  Future<void> resetPassword(String token, String newPassword) async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.post('/auth/reset-password', data: {
      'token': token,
      'new_password': newPassword,
    });
  }

  /// Asks the backend to (re)send the verification email to the signed-in user.
  Future<void> sendVerificationEmail() async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.post('/auth/send-verification-email');
  }

  /// Confirms the email address using the token from the verification link.
  Future<void> verifyEmail(String token) async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.post('/auth/verify-email', queryParameters: {'token': token});
  }
  
  Future<void> completeOnboarding(String accessToken, String refreshToken) async {
    await _storage.saveTokens(access: accessToken, refresh: refreshToken);
    await _storage.setOnboardingCompleted();
    state = AsyncData(AuthState(status: AuthStatus.authenticated));
  }

  // ── Account settings ──────────────────────────────────────────────────────
  /// Changes the signed-in user's password. The backend rotates the session
  /// (signing out every other device) and returns fresh tokens for this client,
  /// which we persist so the current session stays valid.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final apiClient = ref.read(apiClientProvider);
    final response = await apiClient.post('/account/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    await _storage.saveTokens(
      access: response.data['access_token'],
      refresh: response.data['refresh_token'],
    );
  }

  /// Updates the email address. Requires the current password and re-triggers
  /// email verification for the new address on the backend.
  Future<void> changeEmail(String newEmail, String password) async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.post('/account/change-email', data: {
      'new_email': newEmail,
      'password': password,
    });
  }

  /// Permanently deletes the account, then signs out locally.
  Future<void> deleteAccount(String password) async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.delete('/account', data: {'password': password});
    await _storage.clearAll();
    state = AsyncData(AuthState(status: AuthStatus.unauthenticated));
  }

  /// Revokes sessions on all devices (including this one) and signs out locally.
  Future<void> logoutAllDevices() async {
    final apiClient = ref.read(apiClientProvider);
    try {
      await apiClient.post('/auth/logout-all');
    } catch (_) {
      // Even if the call fails (e.g. token already expired), clear locally.
    }
    await _storage.clearAll();
    state = AsyncData(AuthState(status: AuthStatus.unauthenticated));
  }
}

final authProvider = AsyncNotifierProvider.autoDispose<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
