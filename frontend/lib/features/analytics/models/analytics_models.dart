/// Models for GET /analytics/weekly (Phase-1 polish, part 2). Plain
/// classes, not Hive-persisted — this is always freshly fetched, never
/// needed offline, so there's no adapter-generation risk to worry about
/// here (unlike ActivityState/CGMState elsewhere in this app).
library;

class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange({required this.start, required this.end});

  factory DateRange.fromJson(Map<String, dynamic> json) => DateRange(
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
      );
}

class TIRBreakdown {
  final double below;
  final double target;
  final double above;

  const TIRBreakdown({required this.below, required this.target, required this.above});

  factory TIRBreakdown.fromJson(Map<String, dynamic> json) => TIRBreakdown(
        below: (json['below'] as num).toDouble(),
        target: (json['target'] as num).toDouble(),
        above: (json['above'] as num).toDouble(),
      );
}

class DailyGlucosePoint {
  final DateTime date;
  final double? avgMgdl;
  final int? minMgdl;
  final int? maxMgdl;
  final int readingCount;

  const DailyGlucosePoint({
    required this.date,
    this.avgMgdl,
    this.minMgdl,
    this.maxMgdl,
    this.readingCount = 0,
  });

  factory DailyGlucosePoint.fromJson(Map<String, dynamic> json) => DailyGlucosePoint(
        date: DateTime.parse(json['date'] as String),
        avgMgdl: (json['avg_mgdl'] as num?)?.toDouble(),
        minMgdl: (json['min_mgdl'] as num?)?.toInt(),
        maxMgdl: (json['max_mgdl'] as num?)?.toInt(),
        readingCount: (json['reading_count'] as num?)?.toInt() ?? 0,
      );
}

class GlucoseWeeklySummary {
  final bool hasData;
  final double? averageMgdl;
  final double? gmiPercent;
  final int readingCount;
  final TIRBreakdown? tir;
  final List<DailyGlucosePoint> daily;

  const GlucoseWeeklySummary({
    required this.hasData,
    this.averageMgdl,
    this.gmiPercent,
    this.readingCount = 0,
    this.tir,
    this.daily = const [],
  });

  factory GlucoseWeeklySummary.fromJson(Map<String, dynamic> json) => GlucoseWeeklySummary(
        hasData: json['has_data'] as bool? ?? false,
        averageMgdl: (json['average_mgdl'] as num?)?.toDouble(),
        gmiPercent: (json['gmi_percent'] as num?)?.toDouble(),
        readingCount: (json['reading_count'] as num?)?.toInt() ?? 0,
        tir: json['tir'] != null ? TIRBreakdown.fromJson(json['tir'] as Map<String, dynamic>) : null,
        daily: (json['daily'] as List<dynamic>? ?? [])
            .map((e) => DailyGlucosePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FoodGlucoseCorrelation {
  final String mealId;
  final DateTime mealTime;
  final String label;
  final double? carbsG;
  final int baselineMgdl;
  final int postMealMgdl;
  final int deltaMgdl;
  final String window; // "1hr" | "2hr"
  final String? outcome;

  const FoodGlucoseCorrelation({
    required this.mealId,
    required this.mealTime,
    required this.label,
    this.carbsG,
    required this.baselineMgdl,
    required this.postMealMgdl,
    required this.deltaMgdl,
    required this.window,
    this.outcome,
  });

  factory FoodGlucoseCorrelation.fromJson(Map<String, dynamic> json) => FoodGlucoseCorrelation(
        mealId: json['meal_id'] as String,
        mealTime: DateTime.parse(json['meal_time'] as String),
        label: json['label'] as String,
        carbsG: (json['carbs_g'] as num?)?.toDouble(),
        baselineMgdl: (json['baseline_mgdl'] as num).toInt(),
        postMealMgdl: (json['post_meal_mgdl'] as num).toInt(),
        deltaMgdl: (json['delta_mgdl'] as num).toInt(),
        window: json['window'] as String,
        outcome: json['outcome'] as String?,
      );
}

class DailyMetricPoint {
  final DateTime date;
  final double? value;

  const DailyMetricPoint({required this.date, this.value});

  factory DailyMetricPoint.fromJson(Map<String, dynamic> json) => DailyMetricPoint(
        date: DateTime.parse(json['date'] as String),
        value: (json['value'] as num?)?.toDouble(),
      );
}

class HealthMetricTrend {
  final bool hasData;
  final String unit;
  final List<DailyMetricPoint> daily;

  const HealthMetricTrend({required this.hasData, required this.unit, this.daily = const []});

  factory HealthMetricTrend.fromJson(Map<String, dynamic> json) => HealthMetricTrend(
        hasData: json['has_data'] as bool? ?? false,
        unit: json['unit'] as String? ?? '',
        daily: (json['daily'] as List<dynamic>? ?? [])
            .map((e) => DailyMetricPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class HealthTrends {
  final HealthMetricTrend steps;
  final HealthMetricTrend sleepMinutes;
  final HealthMetricTrend hrv;
  final HealthMetricTrend restingHeartRate;

  const HealthTrends({
    required this.steps,
    required this.sleepMinutes,
    required this.hrv,
    required this.restingHeartRate,
  });

  factory HealthTrends.fromJson(Map<String, dynamic> json) => HealthTrends(
        steps: HealthMetricTrend.fromJson(json['steps'] as Map<String, dynamic>),
        sleepMinutes: HealthMetricTrend.fromJson(json['sleep_minutes'] as Map<String, dynamic>),
        hrv: HealthMetricTrend.fromJson(json['hrv'] as Map<String, dynamic>),
        restingHeartRate: HealthMetricTrend.fromJson(json['resting_heart_rate'] as Map<String, dynamic>),
      );
}

class DailyNutritionPoint {
  final DateTime date;
  final int? calories;
  final double? carbsG;
  final double? proteinG;
  final double? fatG;

  const DailyNutritionPoint({required this.date, this.calories, this.carbsG, this.proteinG, this.fatG});

  factory DailyNutritionPoint.fromJson(Map<String, dynamic> json) => DailyNutritionPoint(
        date: DateTime.parse(json['date'] as String),
        calories: (json['calories'] as num?)?.toInt(),
        carbsG: (json['carbs_g'] as num?)?.toDouble(),
        proteinG: (json['protein_g'] as num?)?.toDouble(),
        fatG: (json['fat_g'] as num?)?.toDouble(),
      );
}

class NutritionTrends {
  final bool hasData;
  final List<DailyNutritionPoint> daily;

  const NutritionTrends({required this.hasData, this.daily = const []});

  factory NutritionTrends.fromJson(Map<String, dynamic> json) => NutritionTrends(
        hasData: json['has_data'] as bool? ?? false,
        daily: (json['daily'] as List<dynamic>? ?? [])
            .map((e) => DailyNutritionPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AnalyticsInsight {
  final String text;
  final String kind;

  const AnalyticsInsight({required this.text, required this.kind});

  factory AnalyticsInsight.fromJson(Map<String, dynamic> json) => AnalyticsInsight(
        text: json['text'] as String,
        kind: json['kind'] as String,
      );
}

class WeeklyAnalytics {
  final DateRange range;
  final GlucoseWeeklySummary glucose;
  final List<FoodGlucoseCorrelation> foodGlucoseCorrelations;
  final HealthTrends healthTrends;
  final NutritionTrends nutritionTrends;
  final List<AnalyticsInsight> insights;

  const WeeklyAnalytics({
    required this.range,
    required this.glucose,
    required this.foodGlucoseCorrelations,
    required this.healthTrends,
    required this.nutritionTrends,
    required this.insights,
  });

  factory WeeklyAnalytics.fromJson(Map<String, dynamic> json) => WeeklyAnalytics(
        range: DateRange.fromJson(json['range'] as Map<String, dynamic>),
        glucose: GlucoseWeeklySummary.fromJson(json['glucose'] as Map<String, dynamic>),
        foodGlucoseCorrelations: (json['food_glucose_correlations'] as List<dynamic>? ?? [])
            .map((e) => FoodGlucoseCorrelation.fromJson(e as Map<String, dynamic>))
            .toList(),
        healthTrends: HealthTrends.fromJson(json['health_trends'] as Map<String, dynamic>),
        nutritionTrends: NutritionTrends.fromJson(json['nutrition_trends'] as Map<String, dynamic>),
        insights: (json['insights'] as List<dynamic>? ?? [])
            .map((e) => AnalyticsInsight.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
