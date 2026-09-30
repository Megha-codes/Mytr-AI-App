/// Food item returned by Gemini Vision image analysis.
class FoodItem {
  final String name;
  final String portion;
  final int portionGrams;

  const FoodItem({
    required this.name,
    required this.portion,
    required this.portionGrams,
  });

  factory FoodItem.fromJson(Map<String, dynamic> json) => FoodItem(
        name: json['name'] as String,
        portion: (json['portion'] as String?) ?? '',
        portionGrams: (json['portion_grams'] as num?)?.toInt() ?? 100,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'portion': portion,
        'portion_grams': portionGrams,
      };

  FoodItem copyWith({int? portionGrams}) => FoodItem(
        name: name,
        portion: portion,
        portionGrams: portionGrams ?? this.portionGrams,
      );
}

/// Nutrition data per 100 g returned by USDA FoodData Central search.
class NutritionData {
  final String name;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final String fdcId;

  const NutritionData({
    required this.name,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.fdcId,
  });

  factory NutritionData.fromJson(Map<String, dynamic> json) => NutritionData(
        name: json['name'] as String,
        calories: (json['calories'] as num).toDouble(),
        proteinG: (json['protein_g'] as num).toDouble(),
        carbsG: (json['carbs_g'] as num).toDouble(),
        fatG: (json['fat_g'] as num).toDouble(),
        fiberG: (json['fiber_g'] as num).toDouble(),
        fdcId: json['fdc_id'] as String,
      );

  /// Scale values from per-100g to the given portion in grams.
  NutritionData scaleToGrams(int grams) {
    final ratio = grams / 100.0;
    return NutritionData(
      name: name,
      calories: calories * ratio,
      proteinG: proteinG * ratio,
      carbsG: carbsG * ratio,
      fatG: fatG * ratio,
      fiberG: fiberG * ratio,
      fdcId: fdcId,
    );
  }
}

/// Saved meal log entry returned by POST /nutrition/log-meal.
class MealLogEntry {
  final String mealId;
  final String foodName;
  final int portionGrams;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double glycaemicLoad;
  // "ifct" | "usda" | "gemini_estimate" | "manual" — which resolution tier
  // actually produced these numbers. See nutritionVerified for the
  // user-facing distinction that matters: a database match vs a guess.
  final String nutritionSource;
  // True for a real database match (IFCT/USDA) or a user-entered manual
  // value; false only for gemini_estimate — a guess with no database hit.
  // This is the field the UI must surface (not nutritionSource directly)
  // so a user can never mistake an estimate for a verified value.
  final bool nutritionVerified;

  const MealLogEntry({
    required this.mealId,
    required this.foodName,
    required this.portionGrams,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.glycaemicLoad,
    required this.nutritionSource,
    required this.nutritionVerified,
  });

  factory MealLogEntry.fromJson(Map<String, dynamic> json) => MealLogEntry(
        mealId: json['meal_id'] as String,
        foodName: json['food_name'] as String,
        portionGrams: (json['portion_grams'] as num).toInt(),
        calories: (json['calories'] as num).toDouble(),
        proteinG: (json['protein_g'] as num).toDouble(),
        carbsG: (json['carbs_g'] as num).toDouble(),
        fatG: (json['fat_g'] as num).toDouble(),
        fiberG: (json['fiber_g'] as num).toDouble(),
        glycaemicLoad: (json['glycaemic_load'] as num).toDouble(),
        nutritionSource: json['nutrition_source'] as String? ?? 'manual',
        nutritionVerified: json['nutrition_verified'] as bool? ?? true,
      );
}

/// One row from GET /nutrition/meals — a single logged food item (one
/// MealLog row = one food; a photographed multi-item meal is several of
/// these sharing the same [mealTime], grouped back into "one meal" by the
/// caller since meal_logs has no explicit grouping column).
class MealSummary {
  final String id;
  final DateTime mealTime;
  final String foodName;
  final int? portionGrams;
  final int? calories;
  final double? carbsG;
  final double? proteinG;
  final double? fatG;
  final double? fiberG;
  final double? glycaemicLoad;
  final String? nutritionSource;
  final bool? nutritionVerified;

  const MealSummary({
    required this.id,
    required this.mealTime,
    required this.foodName,
    this.portionGrams,
    this.calories,
    this.carbsG,
    this.proteinG,
    this.fatG,
    this.fiberG,
    this.glycaemicLoad,
    this.nutritionSource,
    this.nutritionVerified,
  });

  factory MealSummary.fromJson(Map<String, dynamic> json) => MealSummary(
        id: json['id'] as String,
        mealTime: DateTime.parse(json['meal_time'] as String),
        foodName: json['food_name'] as String,
        portionGrams: (json['portion_grams'] as num?)?.toInt(),
        calories: (json['calories'] as num?)?.toInt(),
        carbsG: (json['carbs_g'] as num?)?.toDouble(),
        proteinG: (json['protein_g'] as num?)?.toDouble(),
        fatG: (json['fat_g'] as num?)?.toDouble(),
        fiberG: (json['fiber_g'] as num?)?.toDouble(),
        glycaemicLoad: (json['glycaemic_load'] as num?)?.toDouble(),
        nutritionSource: json['nutrition_source'] as String?,
        nutritionVerified: json['nutrition_verified'] as bool?,
      );
}

/// One real glucose reading, part of a meal's response window.
class GlucoseResponsePoint {
  final DateTime recordedAt;
  final int valueMgdl;

  const GlucoseResponsePoint({required this.recordedAt, required this.valueMgdl});

  factory GlucoseResponsePoint.fromJson(Map<String, dynamic> json) => GlucoseResponsePoint(
        recordedAt: DateTime.parse(json['recorded_at'] as String),
        valueMgdl: (json['value_mgdl'] as num).toInt(),
      );
}

/// GET /nutrition/meals/{id}/glucose-response — the real CGM response
/// around one meal. [hasData] false means no CGM connected or nothing
/// landed in the window yet: render the empty state, never a fake graph.
class MealGlucoseResponse {
  final String mealId;
  final bool hasData;
  final int? targetMin;
  final int? targetMax;
  final int? baselineMgdl;
  final int? postMealMgdl;
  final String? postMealWindow; // "1hr" | "2hr"
  final int? deltaMgdl;
  final String? outcome; // "HYPO" | "LOW" | "IN_RANGE" | "HIGH" | "HYPER"
  final List<GlucoseResponsePoint> readings;

  const MealGlucoseResponse({
    required this.mealId,
    required this.hasData,
    this.targetMin,
    this.targetMax,
    this.baselineMgdl,
    this.postMealMgdl,
    this.postMealWindow,
    this.deltaMgdl,
    this.outcome,
    this.readings = const [],
  });

  factory MealGlucoseResponse.fromJson(Map<String, dynamic> json) => MealGlucoseResponse(
        mealId: json['meal_id'] as String,
        hasData: json['has_data'] as bool,
        targetMin: (json['target_min'] as num?)?.toInt(),
        targetMax: (json['target_max'] as num?)?.toInt(),
        baselineMgdl: (json['baseline_mgdl'] as num?)?.toInt(),
        postMealMgdl: (json['post_meal_mgdl'] as num?)?.toInt(),
        postMealWindow: json['post_meal_window'] as String?,
        deltaMgdl: (json['delta_mgdl'] as num?)?.toInt(),
        outcome: json['outcome'] as String?,
        readings: (json['readings'] as List<dynamic>? ?? [])
            .map((e) => GlucoseResponsePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
