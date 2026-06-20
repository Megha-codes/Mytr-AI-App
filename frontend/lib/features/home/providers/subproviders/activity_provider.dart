import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/models.dart';
import 'dashboard_provider.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/services/health_service.dart';
import '../../../wearables/providers/wearable_provider.dart';
import '../../../wearables/services/google_health_service.dart';

class ActivityNotifier extends AutoDisposeAsyncNotifier<ActivityState> {
  @override
  FutureOr<ActivityState> build() async {
    final dashboard = await ref.watch(dashboardProvider.future);
    return dashboard.activity;
  }

  Future<void> syncWithHealth() async {
    final wearables = ref.read(wearableProvider).valueOrNull;
    if (wearables == null) return;

    int steps = 0, calories = 0, heartRate = 0;
    List<DailyValue> weeklySteps = [];

    // Apple Health (iOS) / Health Connect (Android)
    if (!kIsWeb && wearables.healthConnected) {
      try {
        final result = await HealthService.instance.fetchToday();
        steps = result.steps;
        calories = result.caloriesBurned;
        heartRate = result.heartRate;
        weeklySteps = result.weeklySteps;
      } catch (_) {}
    }

    // Fitbit data via Google Health API — prefer when both sources active
    if (wearables.googleHealthConnected) {
      try {
        final gh = await GoogleHealthService.instance.fetchToday();
        if (gh.steps > steps) steps = gh.steps;
        if (gh.caloriesOut > calories) calories = gh.caloriesOut;
        if (gh.heartRate > 0) heartRate = gh.heartRate;
      } catch (_) {}
    }

    if (steps == 0 && calories == 0) return;

    // Persist to backend
    try {
      await ref.read(apiClientProvider).post('/activity/sync', data: {
        'steps_today': steps,
        'calories_burned': calories,
        'heart_rate': heartRate,
      });
    } catch (_) {}

    // Update UI immediately without waiting for a dashboard refresh
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(ActivityState(
        stepsToday: steps,
        stepTarget: current.stepTarget,
        caloriesBurned: calories,
        activeMinutes: current.activeMinutes,
        heartRate: heartRate,
        stepHistory: weeklySteps.isNotEmpty ? weeklySteps : current.stepHistory,
      ));
    }
  }
}

final activityProvider =
    AsyncNotifierProvider.autoDispose<ActivityNotifier, ActivityState>(
  ActivityNotifier.new,
);
