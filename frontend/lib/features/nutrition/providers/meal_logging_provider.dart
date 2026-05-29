import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../models/food_models.dart';

/// Saves individual food items (from USDA search) to the backend meal_logs
/// table via POST /nutrition/log-meal.
///
/// State holds the last successfully logged [MealLogEntry], or null.
class MealLoggingNotifier extends AutoDisposeAsyncNotifier<MealLogEntry?> {
  @override
  FutureOr<MealLogEntry?> build() => null;

  /// Calculates macros server-side and persists the meal.
  ///
  /// [foodItem] — the Gemini-identified food (name + portion_grams).
  /// [nutrition] — USDA nutrition per 100 g for this food.
  /// [portionGrams] — the user's chosen portion; overrides foodItem.portionGrams.
  Future<MealLogEntry?> saveFood({
    required FoodItem foodItem,
    required NutritionData nutrition,
    int? portionGrams,
    DateTime? mealTime,
  }) async {
    state = const AsyncLoading();

    final portion = portionGrams ?? foodItem.portionGrams;

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/nutrition/log-meal',
        data: {
          'food_name': foodItem.name,
          'portion_grams': portion,
          'fdc_id': nutrition.fdcId,
          'meal_time': (mealTime ?? DateTime.now().toUtc()).toIso8601String(),
          'calories_per_100g': nutrition.calories,
          'protein_per_100g': nutrition.proteinG,
          'carbs_per_100g': nutrition.carbsG,
          'fat_per_100g': nutrition.fatG,
          'fiber_per_100g': nutrition.fiberG,
        },
      );

      final entry = MealLogEntry.fromJson(
        response.data as Map<String, dynamic>,
      );
      state = AsyncData(entry);
      return entry;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  void reset() => state = const AsyncData(null);
}

final mealLoggingProvider =
    AsyncNotifierProvider.autoDispose<MealLoggingNotifier, MealLogEntry?>(
  MealLoggingNotifier.new,
);
