import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/auth_storage_service.dart';
import '../../../core/api/api_client.dart';
import '../../chat/providers/chat_provider.dart';
import '../../devices/providers/device_list_provider.dart';
import '../../cgm/providers/cgm_connection_provider.dart';
import '../../home/providers/subproviders/inference_provider.dart';
import '../../profile/providers/goals_provider.dart';
import '../../wearables/providers/wearable_provider.dart';

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
  
  /// Wipes every piece of THIS user's state that could otherwise survive
  /// into the next signed-in user's session on the same device — logout
  /// never restarts the app process, so anything not explicitly cleared
  /// here just... stays, in memory or on disk, for whoever logs in next.
  ///
  /// _storage.clearAll() (AuthStorageService) only ever owned the token
  /// pair + a couple of onboarding flags. Everything below is a SEPARATE
  /// cache that clearAll() was never wired to reach:
  ///   - goalsProvider persists to its own private secure-storage key
  ///     ('user_goals', in goals_provider.dart) entirely outside
  ///     AuthStorageService — clear() wipes that key AND the in-memory
  ///     state (a bare invalidate would just re-read the still-populated
  ///     key and hand the next user the same "leaked" goals right back).
  ///   - The rest are plain in-memory Riverpod state with no local
  ///     persistence, but most feature providers in this app are
  ///     `.autoDispose` and get torn down for free once the router
  ///     unmounts the authenticated screens on logout. These six are the
  ///     ones that were NOT (chat/inference/deviceList weren't autoDispose
  ///     at all; wearable/cgmConnection still aren't, by design — they can
  ///     legitimately need to survive navigation mid-flow) — ref.invalidate
  ///     forces every one of them back to a fresh build() regardless of
  ///     whether anything happens to still be watching them, so this
  ///     doesn't depend on incidental widget-tree timing being right.
  /// chatProvider held the previous user's actual conversation (the
  /// chatbot answers with their real health data); inferenceProvider held
  /// a computed insulin dose recommendation for their physiology — these
  /// two are the ones where "stale" isn't just wrong, it's dangerous.
  ///
  /// RULE FOR ANY NEW USER-SCOPED PROVIDER (fetched-from-backend state,
  /// anything typed in, anything computed from either): it needs BOTH of
  /// the following, not just one —
  ///   1. `.autoDispose` on the provider declaration, so it doesn't outlive
  ///      whatever screen actually needed it, AND
  ///   2. an explicit `ref.invalidate(...)` line added right here.
  /// `.autoDispose` alone isn't sufficient — it only tears the provider
  /// down once its LAST watcher unmounts, which depends on the router
  /// actually unmounting every screen that was watching it, and is exactly
  /// the kind of "probably fine" widget-tree timing this method exists to
  /// not depend on. An explicit invalidate() alone isn't sufficient either
  /// if the provider persists to its own storage (see goalsProvider.clear()
  /// above) — invalidating without wiping storage just rebuilds the same
  /// leaked value straight back out of disk. Skipping either one silently
  /// reopens this exact bug for that provider. See
  /// test/features/auth/logout_cross_user_test.dart, which exists
  /// specifically to catch that regression — extend it (don't just add a
  /// new standalone test) when you add a provider here.
  Future<void> _clearAllUserState() async {
    await ref.read(goalsProvider.notifier).clear();
    await _storage.clearAll();
    ref.invalidate(chatProvider);
    ref.invalidate(inferenceProvider);
    ref.invalidate(deviceListProvider);
    ref.invalidate(wearableProvider);
    ref.invalidate(cgmConnectionProvider);
  }

  Future<void> logout() async {
    await _clearAllUserState();
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
    await _clearAllUserState();
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
    await _clearAllUserState();
    state = AsyncData(AuthState(status: AuthStatus.unauthenticated));
  }
}

final authProvider = AsyncNotifierProvider.autoDispose<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
