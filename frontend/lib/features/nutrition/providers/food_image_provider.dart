import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../models/food_models.dart';
import '../services/meal_recognition_service.dart';

/// Holds the result of a Gemini Vision image analysis.
/// State is null before the first call, loading during the API call,
/// and a list of [FoodItem]s (possibly empty) on success.
class FoodImageNotifier extends AutoDisposeAsyncNotifier<List<FoodItem>> {
  @override
  FutureOr<List<FoodItem>> build() => [];

  /// Encodes [imageFile] to base64 and sends it to Gemini Vision via
  /// POST /nutrition/analyze-image. Updates state with the identified foods.
  Future<void> analyzeImage(File imageFile) async {
    state = const AsyncLoading();

    try {
      final service = FoodRecognitionService(ref.read(apiClientProvider));
      final items = await service.analyzeImage(imageFile);
      state = AsyncData(items);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  void reset() => state = const AsyncData([]);
}

final foodImageProvider =
    AsyncNotifierProvider.autoDispose<FoodImageNotifier, List<FoodItem>>(
  FoodImageNotifier.new,
);
