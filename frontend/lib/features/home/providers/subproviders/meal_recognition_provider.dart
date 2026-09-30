import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../models/models.dart';
import '../../../nutrition/models/food_models.dart';
import '../../../nutrition/providers/meal_logging_provider.dart';
import '../../../nutrition/services/meal_recognition_service.dart';
import 'dashboard_provider.dart';

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
  // Raw Gemini-detected items (name + portion_grams), retained so
  // confirmAndLog can resolve+log each one for real through the backend's
  // actual IFCT -> USDA -> Gemini chain, rather than the totals above
  // (which are only ever a client-side USDA-only preview shown before the
  // user confirms — never what gets persisted).
  final List<FoodItem> foodItems;
  // Shared across every item logged from this one capture, so they can
  // later be grouped back into "one meal" (meal_logs has no explicit
  // grouping column — same meal_time is the join key).
  final DateTime mealTime;

  RecognitionResult({
    required this.meal,
    required this.confidence,
    required this.detectedItems,
    this.requiresConfirmation = false,
    this.confirmationMessage,
    this.foodItems = const [],
    DateTime? mealTime,
  }) : mealTime = mealTime ?? DateTime.now();
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
      final mealTime = DateTime.now();

      final meal = LoggedMeal(
        id: '',
        name: mealName,
        timestamp: mealTime,
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
        foodItems: foodItems,
        mealTime: mealTime,
      ));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Logs every detected item individually through POST /nutrition/log-meal
  /// (no pre-supplied numbers — the backend's real IFCT -> USDA -> Gemini
  /// resolver decides each one), so each ends up with its own honest
  /// nutrition_source/nutrition_verified instead of one combined "manual,
  /// always verified" row. Returns the logged entries (empty if every item
  /// failed) so a caller can show what was actually persisted; throws if
  /// there's nothing to log at all (recognizeMeal was never called, or
  /// found zero items).
  ///
  /// Note: not atomic — if some items succeed and one fails partway
  /// through, the successful ones are already real, committed MealLog
  /// rows; there's no rollback. Acceptable here since each row is
  /// independently correct and editable/deletable on its own via the
  /// existing PATCH/DELETE /nutrition/meals/{id} routes.
  Future<List<MealLogEntry>> confirmAndLog() async {
    final result = state.value;
    if (result == null || result.foodItems.isEmpty) {
      throw StateError('No recognized food items to log');
    }

    final logged = <MealLogEntry>[];
    for (final item in result.foodItems) {
      final entry = await ref.read(mealLoggingProvider.notifier).logDetectedItem(
            foodItem: item,
            mealTime: result.mealTime,
          );
      if (entry != null) logged.add(entry);
    }

    ref.invalidate(dashboardProvider);
    state = const AsyncData(null);
    return logged;
  }

  void reset() => state = const AsyncData(null);
}

// ── Provider ──────────────────────────────────────────────────────────────────

final mealRecognitionProvider =
    AsyncNotifierProvider.autoDispose<MealRecognitionNotifier, RecognitionResult?>(
  MealRecognitionNotifier.new,
);
