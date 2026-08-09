import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/config/environment.dart';
import 'core/routing/router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/health_service.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/home/models/models.dart';
import 'features/wearables/services/health_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize configuration
  await Environment.init();

  // Must happen this early, not lazily on first screen visit (which is what
  // WearableNotifier.build() would otherwise do first): the health plugin's
  // Android implementation registers an ActivityResultLauncher to actually
  // show the Health Connect permission screen, and Android only allows that
  // registration before the Activity reaches its "started" state. Configure
  // after that point and requestAuthorization() fails silently — no
  // permission screen, no exception, just native "Permission launcher not
  // found" logs (FLUTTER_HEALTH tag) that never reach Dart at all. Wrapped
  // in try/catch so a plugin hiccup here can't block app startup entirely.
  try {
    await HealthService.instance.configure();
  } catch (_) {}

  // Initialize Hive
  await Hive.initFlutter();

  // Register Adapters
  Hive.registerAdapter(UserProfileAdapter());
  Hive.registerAdapter(ActivitySummaryAdapter());
  Hive.registerAdapter(SleepDataAdapter());
  Hive.registerAdapter(SleepStageAdapter());
  Hive.registerAdapter(SleepStageTypeAdapter());
  Hive.registerAdapter(CoachInsightAdapter());
  Hive.registerAdapter(WeightEntryAdapter());
  Hive.registerAdapter(NutritionSummaryAdapter());
  Hive.registerAdapter(LoggedMealAdapter());
  Hive.registerAdapter(GlucosePointAdapter());
  Hive.registerAdapter(TIRBreakdownAdapter());
  Hive.registerAdapter(CGMStateAdapter());
  Hive.registerAdapter(NutritionStateAdapter());
  Hive.registerAdapter(ActivityStateAdapter());
  Hive.registerAdapter(CoachStateAdapter());
  Hive.registerAdapter(SensorStatusAdapter());
  Hive.registerAdapter(CGMDeviceAdapter());
  Hive.registerAdapter(DailyValueAdapter());
  Hive.registerAdapter(ChallengeCategoryAdapter());
  Hive.registerAdapter(ChallengeAdapter());

  runApp(const ProviderScope(child: MytrAiApp()));
}

class MytrAiApp extends ConsumerStatefulWidget {
  const MytrAiApp({super.key});

  @override
  ConsumerState<MytrAiApp> createState() => _MytrAiAppState();
}

class _MytrAiAppState extends ConsumerState<MytrAiApp> with WidgetsBindingObserver {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  // Auto sign-out after a period of no user interaction.
  static const _inactivityTimeout = Duration(minutes: 30);
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();
    _resetInactivityTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Best-effort — HealthSyncService itself no-ops when no wearable is
      // connected and never throws past its own boundary, so this is safe
      // to fire unconditionally on every foreground.
      unawaited(ref.read(healthSyncServiceProvider).sync());
    }
  }

  /// Restart the idle countdown. Called on every pointer interaction.
  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, _onInactivityTimeout);
  }

  Future<void> _onInactivityTimeout() async {
    final auth = ref.read(authProvider).valueOrNull;
    if (auth?.status != AuthStatus.authenticated) return;
    await ref.read(authProvider.notifier).logout();
    if (mounted) ref.read(appRouterProvider).go('/auth/login');
  }

  Future<void> _initDeepLinks() async {
    // Handle the link that cold-started the app.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (_) {}
    // Handle links that arrive while the app is running.
    _linkSub = _appLinks.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  /// Maps `mytrai://<host>?token=...` deep links onto in-app routes.
  void _handleUri(Uri uri) {
    final token = uri.queryParameters['token'];
    String? path;
    switch (uri.host) {
      case 'reset-password':
        path = '/auth/reset-password';
        break;
      case 'verify-email':
        path = '/auth/verify-email';
        break;
    }
    if (path == null) return;

    final location = Uri(
      path: path,
      queryParameters: token != null ? {'token': token} : null,
    ).toString();
    ref.read(appRouterProvider).go(location);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Mytr.AI',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetInactivityTimer(),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
