import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../models/models.dart';
import '../../../nutrition/models/food_models.dart';
import '../../../nutrition/services/meal_recognition_service.dart';
import 'nutrition_provider.dart';

// ── Internal detail type (not exposed to UI) ──────────────────────────────────

class _RecognizedFood {
  final FoodItem item;
  final NutritionData nutrition;

  const _RecognizedFood({required this.item, required this.nutrition});
}

// ── Public state type (UI reads these fields) ─────────────────────────────────

class RecognitionResult {
  final LoggedMeal meal;
  final double confidence;
  final List<String> detectedItems;
  final bool requiresConfirmation;
  final String? confirmationMessage;

  RecognitionResult({
    required this.meal,
    required this.confidence,
    required this.detectedItems,
    this.requiresConfirmation = false,
    this.confirmationMessage,
  });
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class MealRecognitionNotifier
    extends AutoDisposeAsyncNotifier<RecognitionResult?> {
  @override
  FutureOr<RecognitionResult?> build() => null;

  /// Sends [imageFile] to Gemini Vision, looks up USDA nutrition for each
  /// identified food, then exposes a [RecognitionResult] with totals.
  Future<void> recognizeMeal(File imageFile) async {
    state = const AsyncLoading();

    try {
      final service = FoodRecognitionService(ref.read(apiClientProvider));

      // 1. Gemini Vision: get food items + estimated portions
      final foodItems = await service.analyzeImage(imageFile);

      if (foodItems.isEmpty) {
        state = AsyncData(RecognitionResult(
          meal: LoggedMeal(
            id: '',
            name: 'Meal',
            timestamp: DateTime.now(),
            calories: 0,
            carbsG: 0,
            proteinG: 0,
            fatG: 0,
          ),
          confidence: 0.0,
          detectedItems: [],
          requiresConfirmation: true,
          confirmationMessage:
              'No food items were detected. Please try a clearer photo.',
        ));
        return;
      }

      // 2. USDA: look up nutrition per 100 g for each detected food
      final recognized = <_RecognizedFood>[];

      for (final item in foodItems) {
        try {
          final results = await service.searchFood(item.name);
          if (results.isNotEmpty) {
            recognized.add(_RecognizedFood(item: item, nutrition: results.first));
          }
        } catch (_) {
          // Skip items that fail USDA lookup; totals will reflect what we have.
        }
      }

      // 3. Compute scaled totals (portion_grams / 100 × per-100g values)
      var totalCalories = 0.0;
      var totalCarbs = 0.0;
      var totalProtein = 0.0;
      var totalFat = 0.0;
      final detectedNames = foodItems.map((f) => f.name).toList();

      for (final r in recognized) {
        final scaled = r.nutrition.scaleToGrams(r.item.portionGrams);
        totalCalories += scaled.calories;
        totalCarbs += scaled.carbsG;
        totalProtein += scaled.proteinG;
        totalFat += scaled.fatG;
      }

      final mealName = detectedNames.join(', ');

      final meal = LoggedMeal(
        id: '',
        name: mealName,
        timestamp: DateTime.now(),
        calories: totalCalories.round(),
        carbsG: totalCarbs.round(),
        proteinG: totalProtein.round(),
        fatG: totalFat.round(),
        glycaemicLoad: 0.0,
        estimatedRiseMinutes: 0,
      );

      state = AsyncData(RecognitionResult(
        meal: meal,
        confidence: 0.85,
        detectedItems: detectedNames,
        requiresConfirmation: recognized.isEmpty,
        confirmationMessage: recognized.isEmpty
            ? 'Could not find nutrition data for the detected foods. '
                'Please verify before logging.'
            : null,
      ));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Logs the recognised meal via the existing /nutrition/log endpoint,
  /// then invalidates the dashboard so nutrition cards refresh.
  Future<void> confirmAndLog() async {
    if (!state.hasValue || state.value == null) return;

    final meal = state.value!.meal;
    await ref.read(nutritionProvider.notifier).logMeal(meal);
    state = const AsyncData(null);
  }

  void reset() => state = const AsyncData(null);
}

// ── Provider ──────────────────────────────────────────────────────────────────

final mealRecognitionProvider =
    AsyncNotifierProvider.autoDispose<MealRecognitionNotifier, RecognitionResult?>(
  MealRecognitionNotifier.new,
);
