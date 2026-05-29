import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../models/models.dart';
import 'dashboard_provider.dart';

// ── Nutrition provider — derived from dashboardProvider ───────────────────────

class NutritionNotifier extends AutoDisposeAsyncNotifier<NutritionState> {
  @override
  FutureOr<NutritionState> build() async {
    final dashboard = await ref.watch(dashboardProvider.future);
    return dashboard.nutrition;
  }

  Future<void> refresh() async {
    ref.invalidate(dashboardProvider);
  }

  Future<void> logMeal(LoggedMeal meal) async {
    await ref.read(apiClientProvider).post('/nutrition/log', data: {
      'name': meal.name,
      'calories': meal.calories,
      'carbs_g': meal.carbsG.toDouble(),
      'protein_g': meal.proteinG.toDouble(),
      'fat_g': meal.fatG.toDouble(),
      'meal_time': meal.timestamp.toUtc().toIso8601String(),
    });
    // Invalidate dashboard so nutrition card refreshes
    ref.invalidate(dashboardProvider);
  }
}

final nutritionProvider =
    AsyncNotifierProvider.autoDispose<NutritionNotifier, NutritionState>(
  NutritionNotifier.new,
);
