import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/config/environment.dart';
import 'core/routing/router.dart';
import 'core/theme/app_theme.dart';
import 'features/home/models/models.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize configuration
  await Environment.init();

  // Initialize Hive
  await Hive.initFlutter();

  // Register Adapters
  Hive.registerAdapter(UserTypeAdapter());
  Hive.registerAdapter(AchievementAdapter());
  Hive.registerAdapter(UserProfileAdapter());
  Hive.registerAdapter(GlucoseTrendAdapter());
  Hive.registerAdapter(GlucoseStatusAdapter());
  Hive.registerAdapter(GlucoseReadingAdapter());
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

class MytrAiApp extends ConsumerWidget {
  const MytrAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Mytr.AI',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
