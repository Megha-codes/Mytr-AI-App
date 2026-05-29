import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the authenticated user's ID after login.
///
/// Initially null (unauthenticated).
/// Set this after a successful auth flow so all features
/// can read the current user ID from one source of truth
/// instead of using the old '_demoUserId' constant.
///
/// Example:
///   ref.read(authSessionProvider.notifier).setUserId(response.userId);
class AuthSessionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setUserId(String id) => state = id;
  void clearSession() => state = null;
}

final authSessionProvider = NotifierProvider<AuthSessionNotifier, String?>(() {
  return AuthSessionNotifier();
});

/// Convenience accessor — throws if no session is active.
/// Use this inside providers that require a logged-in user.
String requireUserId(Ref ref) {
  final userId = ref.watch(authSessionProvider);
  if (userId == null) {
    throw StateError(
      'requireUserId() called but no auth session is active. '
      'Ensure the user has logged in before accessing this provider.',
    );
  }
  return userId;
}
