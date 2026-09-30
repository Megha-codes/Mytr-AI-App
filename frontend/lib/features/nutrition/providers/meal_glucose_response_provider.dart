import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../models/food_models.dart';

/// GET /nutrition/meals/{id}/glucose-response for one meal (any item's id
/// from the group — see GroupedMeal.representativeMealId). Family-keyed by
/// meal id so each meal-detail screen instance fetches independently.
class MealGlucoseResponseNotifier
    extends AutoDisposeFamilyAsyncNotifier<MealGlucoseResponse, String> {
  @override
  Future<MealGlucoseResponse> build(String mealId) async {
    final response = await ref
        .read(apiClientProvider)
        .get('/nutrition/meals/$mealId/glucose-response');
    return MealGlucoseResponse.fromJson(response.data as Map<String, dynamic>);
  }
}

final mealGlucoseResponseProvider = AsyncNotifierProvider.autoDispose
    .family<MealGlucoseResponseNotifier, MealGlucoseResponse, String>(
  MealGlucoseResponseNotifier.new,
);
