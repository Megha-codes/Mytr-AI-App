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
