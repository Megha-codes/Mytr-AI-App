import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../models/food_models.dart';
import '../services/meal_recognition_service.dart';

/// Manages USDA food search results with 500 ms debounce on rapid queries.
class FoodSearchNotifier extends AutoDisposeAsyncNotifier<List<NutritionData>> {
  Timer? _debounce;

  @override
  FutureOr<List<NutritionData>> build() {
    ref.onDispose(() => _debounce?.cancel());
    return [];
  }

  /// Search USDA FoodData Central for [query]. Debounced to 500 ms so rapid
  /// keystrokes don't hammer the API.
  void searchFood(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = const AsyncData([]);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () => _fetch(query));
  }

  Future<void> _fetch(String query) async {
    state = const AsyncLoading();

    try {
      final service = FoodRecognitionService(ref.read(apiClientProvider));
      final results = await service.searchFood(query);
      state = AsyncData(results);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  void clear() {
    _debounce?.cancel();
    state = const AsyncData([]);
  }

}

final foodSearchProvider =
    AsyncNotifierProvider.autoDispose<FoodSearchNotifier, List<NutritionData>>(
  FoodSearchNotifier.new,
);
