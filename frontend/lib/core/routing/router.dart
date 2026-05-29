import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../navigation/main_shell.dart';
import '../../features/profile/providers/user_profile_provider.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/ui/screens/login_screen.dart';
import '../../features/home/ui/screens/home_screen.dart';
import '../../features/home/ui/screens/glucose_screen.dart';
import '../../features/home/ui/screens/activity_screen.dart';
import '../../features/home/ui/screens/meals_screen.dart';
import '../../features/home/ui/screens/coach_screen.dart';
import '../../features/profile/ui/screens/profile_screen.dart';
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
import '../../features/cgm/ui/screens/dexcom_connect_screen.dart';
import '../../features/cgm/ui/screens/libre_connect_screen.dart';
import '../../features/cgm/ui/screens/manual_connect_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: Listenable.merge([
      // Add any other listenables if needed
    ]),
    redirect: (context, state) {
      final status = authState.valueOrNull?.status;
      final location = state.uri.path;

      if (authState.isLoading) return null;

      if (status == AuthStatus.onboardingRequired) {
        if (!location.startsWith('/onboarding') && !location.startsWith('/cgm')) return '/onboarding/intro';
      } else if (status == AuthStatus.unauthenticated) {
        if (location != '/auth/login') return '/auth/login';
      } else if (status == AuthStatus.authenticated) {
        if (location == '/auth/login' || location.startsWith('/onboarding')) return '/home';
      }

      return null;
    },
    routes: [
      // ── Auth ──────────────────────────────────────────────────────────
      GoRoute(
        path: '/auth/login',
        builder: (_, state) {
          final prefillEmail = state.extra as String?;
          return LoginScreen(prefillEmail: prefillEmail);
        },
      ),

      // ── Onboarding flow ────────────────────────────────────────────────
      GoRoute(
        path: '/onboarding/intro',
        builder: (_, _) => const IntroScreen(),
      ),
      GoRoute(
        path: '/onboarding/create-account',
        builder: (_, _) => const CreateAccountScreen(),
      ),
      GoRoute(
        path: '/onboarding/user-type',
        builder: (_, _) => const UserTypeScreen(),
      ),
      GoRoute(
        path: '/onboarding/personal-info',
        builder: (_, _) => const PersonalInfoScreen(),
      ),
      GoRoute(
        path: '/onboarding/insulin-profile',
        builder: (_, _) => const InsulinProfileScreen(),
      ),
      GoRoute(
        path: '/onboarding/lifestyle',
        builder: (_, _) => const LifestyleScreen(),
      ),
      GoRoute(
        path: '/onboarding/devices',
        builder: (_, _) => const DevicesScreen(),
      ),
      GoRoute(
        path: '/onboarding/acknowledgement',
        builder: (_, _) => const AcknowledgementScreen(),
      ),

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
          GoRoute(
            path: '/coach',
            builder: (_, _) => const CoachScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => const ProfileScreen(),
          ),
        ],
      ),

      // ── Standalone routes ──────────────────────────────────────────────
      GoRoute(
        path: '/meals',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const MealsScreen(),
      ),
      GoRoute(
        path: '/cgm/dexcom-connect',
        builder: (context, state) => DexcomConnectScreen(redirectTo: state.extra as String? ?? '/home'),
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
