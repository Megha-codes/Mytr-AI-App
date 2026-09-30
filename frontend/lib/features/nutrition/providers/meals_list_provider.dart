import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../models/food_models.dart';

/// One physical meal — one or more [MealSummary] rows (MealLog has no
/// grouping column) that share the exact meal_time every item logged from
/// the same capture is stamped with (see meal_recognition_provider.dart).
class GroupedMeal {
  final DateTime mealTime;
  final List<MealSummary> items;

  const GroupedMeal({required this.mealTime, required this.items});

  int get totalCalories => items.fold(0, (sum, i) => sum + (i.calories ?? 0));
  double get totalCarbsG => items.fold(0.0, (sum, i) => sum + (i.carbsG ?? 0));
  double get totalProteinG => items.fold(0.0, (sum, i) => sum + (i.proteinG ?? 0));
  double get totalFatG => items.fold(0.0, (sum, i) => sum + (i.fatG ?? 0));
  double get totalFiberG => items.fold(0.0, (sum, i) => sum + (i.fiberG ?? 0));
  double get totalGlycaemicLoad => items.fold(0.0, (sum, i) => sum + (i.glycaemicLoad ?? 0));

  /// Representative id for calls that operate on "this meal" as a whole
  /// (currently just the glucose-response fetch) rather than one item —
  /// every item in the group shares the same meal_time, so the backend's
  /// per-meal_id baseline/post-meal/outcome computation is identical
  /// regardless of which one is used.
  String get representativeMealId => items.first.id;

  String get label => items.map((i) => i.foodName).join(', ');
}

List<GroupedMeal> groupMealsByTime(List<MealSummary> meals) {
  final byTime = <DateTime, List<MealSummary>>{};
  for (final meal in meals) {
    byTime.putIfAbsent(meal.mealTime, () => []).add(meal);
  }
  final groups = byTime.entries
      .map((e) => GroupedMeal(mealTime: e.key, items: e.value))
      .toList();
  groups.sort((a, b) => b.mealTime.compareTo(a.mealTime)); // newest first
  return groups;
}

/// Today's logged meals, grouped. Powers the "Today's meals" list that's
/// the entry point into the meal-detail screen.
class TodaysMealsNotifier extends AutoDisposeAsyncNotifier<List<GroupedMeal>> {
  @override
  Future<List<GroupedMeal>> build() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc();
    final response = await ref.read(apiClientProvider).get(
          '/nutrition/meals',
          queryParameters: {'from': startOfDay.toIso8601String()},
        );
    final data = response.data as Map<String, dynamic>;
    final meals = (data['meals'] as List<dynamic>)
        .map((e) => MealSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    return groupMealsByTime(meals);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final todaysMealsProvider =
    AsyncNotifierProvider.autoDispose<TodaysMealsNotifier, List<GroupedMeal>>(
  TodaysMealsNotifier.new,
);
