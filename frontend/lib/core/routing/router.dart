import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../navigation/main_shell.dart';
import '../../features/profile/providers/user_profile_provider.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/ui/screens/login_screen.dart';
import '../../features/auth/ui/screens/forgot_password_screen.dart';
import '../../features/auth/ui/screens/reset_password_screen.dart';
import '../../features/auth/ui/screens/verify_email_screen.dart';
import '../../features/home/ui/screens/home_screen.dart';
import '../../features/home/ui/screens/glucose_screen.dart';
import '../../features/home/ui/screens/activity_screen.dart';
import '../../features/home/ui/screens/meals_screen.dart';
import '../../features/home/ui/screens/coach_screen.dart';
import '../../features/profile/ui/screens/profile_screen.dart';
import '../../features/profile/ui/screens/goals_screen.dart';
import '../../features/profile/ui/screens/account_settings_screen.dart';
import '../../features/devices/ui/screens/device_management_screen.dart';
import '../../features/devices/ui/screens/pair_device_screen.dart';
import '../../features/home/models/models.dart';

// Onboarding screens
import '../../features/onboarding/ui/screens/intro_screen.dart';
import '../../features/onboarding/ui/screens/create_account_screen.dart';
import '../../features/onboarding/ui/screens/user_type_screen.dart';
import '../../features/onboarding/ui/screens/personal_info_screen.dart';
import '../../features/onboarding/ui/screens/insulin_profile_screen.dart';
import '../../features/onboarding/ui/screens/lifestyle_screen.dart';
import '../../features/onboarding/ui/screens/devices_screen.dart';
import '../../features/onboarding/ui/screens/acknowledgement_screen.dart';

// CGM connect screens
import '../../features/cgm/ui/screens/libre_connect_screen.dart';
import '../../features/cgm/ui/screens/manual_connect_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

// Notifies GoRouter whenever authProvider state changes so redirects re-run.
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(Ref ref) {
    ref.listen<AsyncValue<AuthState>>(authProvider, (_, _) => notifyListeners());
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/onboarding/intro',
    refreshListenable: notifier,
    redirect: (context, state) {
      // Always read current auth state — never use a captured variable here.
      final authState = ref.read(authProvider);
      final status = authState.valueOrNull?.status;
      final location = state.uri.path;

      if (authState.isLoading) return null;

      if (status == AuthStatus.onboardingRequired) {
        if (!location.startsWith('/onboarding') &&
            !location.startsWith('/cgm') &&
            !location.startsWith('/auth/')) {
          return '/onboarding/intro';
        }
      } else if (status == AuthStatus.unauthenticated) {
        // Allow all public auth routes (login, forgot/reset password).
        if (!location.startsWith('/auth/')) return '/auth/login';
      } else if (status == AuthStatus.authenticated) {
        if (location == '/auth/login' || location.startsWith('/onboarding')) {
          return '/home';
        }
      }

      return null;
    },
    routes: [
      // ── Auth ──────────────────────────────────────────────────────────
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => LoginScreen(),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        // Reachable via the reset link (mytrai://reset-password?token=...) once
        // deep linking is wired, or directly with the token pasted manually.
        path: '/auth/reset-password',
        builder: (context, state) => ResetPasswordScreen(
          token: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        // Shown after signup (no token) and reached via the verification deep
        // link (mytrai://verify-email?token=...).
        path: '/auth/verify-email',
        builder: (context, state) => VerifyEmailScreen(
          token: state.uri.queryParameters['token'],
        ),
      ),

      // ── Onboarding flow ────────────────────────────────────────────────
      GoRoute(path: '/onboarding/intro',           builder: (_, _) => const IntroScreen()),
      GoRoute(path: '/onboarding/create-account',  builder: (_, _) => const CreateAccountScreen()),
      GoRoute(path: '/onboarding/user-type',        builder: (_, _) => const UserTypeScreen()),
      GoRoute(path: '/onboarding/personal-info',    builder: (_, _) => const PersonalInfoScreen()),
      GoRoute(path: '/onboarding/insulin-profile',  builder: (_, _) => const InsulinProfileScreen()),
      GoRoute(path: '/onboarding/lifestyle',        builder: (_, _) => const LifestyleScreen()),
      GoRoute(path: '/onboarding/devices',          builder: (_, _) => const DevicesScreen()),
      GoRoute(path: '/onboarding/acknowledgement',  builder: (_, _) => const AcknowledgementScreen()),

      // ── Main app shell ─────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const HomeScreen(),
          ),
          GoRoute(
            path: '/glucose',
            builder: (_, _) => const GlucoseScreen(),
            redirect: (context, state) {
              final userType = ref.read(userProfileProvider).valueOrNull?.userType;
              if (userType == UserType.fitness) return '/activity';
              return null;
            },
          ),
          GoRoute(
            path: '/activity',
            builder: (_, _) => const ActivityScreen(),
            redirect: (context, state) {
              final userType = ref.read(userProfileProvider).valueOrNull?.userType;
              if (userType != null && userType != UserType.fitness) return '/glucose';
              return null;
            },
          ),
          GoRoute(path: '/coach',   builder: (_, _) => const CoachScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),

      // ── Profile sub-routes ────────────────────────────────────────────
      GoRoute(path: '/profile/stats-edit',     builder: (_, _) => const _ComingSoonScreen(title: 'Personal Stats')),
      GoRoute(path: '/profile/goals',          builder: (_, _) => const GoalsScreen()),
      GoRoute(path: '/profile/devices',        builder: (_, _) => const _ComingSoonScreen(title: 'Connected Devices')),
      // The desk display unit (architecture-v3.md §2.2) — a physical
      // pairable device, distinct from the CGM/wearables tracked at
      // /profile/devices above.
      GoRoute(path: '/profile/desk-device',      builder: (_, _) => const DeviceManagementScreen()),
      GoRoute(path: '/profile/desk-device/pair', builder: (_, _) => const PairDeviceScreen()),
      GoRoute(path: '/profile/achievements',   builder: (_, _) => const _ComingSoonScreen(title: 'Achievements')),
      GoRoute(path: '/profile/insulin',        builder: (_, _) => const _ComingSoonScreen(title: 'Insulin Profile')),
      GoRoute(path: '/profile/glucose-target', builder: (_, _) => const _ComingSoonScreen(title: 'Glucose Target')),
      GoRoute(path: '/profile/notifications',  builder: (_, _) => const _ComingSoonScreen(title: 'Notifications')),
      GoRoute(path: '/profile/units',          builder: (_, _) => const _ComingSoonScreen(title: 'Units')),
      GoRoute(path: '/profile/account',        builder: (_, _) => const AccountSettingsScreen()),
      GoRoute(path: '/profile/privacy',        builder: (_, _) => const _ComingSoonScreen(title: 'Privacy & Data')),

      // ── Standalone routes ──────────────────────────────────────────────
      GoRoute(
        path: '/meals',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const MealsScreen(),
      ),
      GoRoute(
        path: '/cgm/libre-connect',
        builder: (context, state) => LibreConnectScreen(redirectTo: state.extra as String? ?? '/home'),
      ),
      GoRoute(
        path: '/cgm/manual-connect',
        builder: (context, state) => ManualConnectScreen(redirectTo: state.extra as String? ?? '/home'),
      ),
    ],
  );
});

class _ComingSoonScreen extends StatelessWidget {
  final String title;
  const _ComingSoonScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(
        child: Text('Coming soon', style: TextStyle(fontSize: 18, color: Colors.grey)),
      ),
    );
  }
}
