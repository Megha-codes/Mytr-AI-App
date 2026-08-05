import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../models/models.dart';

// ── Parsed dashboard response ─────────────────────────────────────────────────
class DashboardData {
  final CGMState cgm;
  final NutritionState nutrition;
  final ActivityState activity;
  final List<Challenge> challenges;

  const DashboardData({
    required this.cgm,
    required this.nutrition,
    required this.activity,
    required this.challenges,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final g = json['glucose'] as Map<String, dynamic>;
    final n = json['nutrition'] as Map<String, dynamic>;
    final a = json['activity'] as Map<String, dynamic>;
    final c = (json['challenges'] as List<dynamic>?) ?? [];

    return DashboardData(
      cgm: _parseCgm(g),
      nutrition: _parseNutrition(n),
      activity: _parseActivity(a),
      challenges: _parseChallenges(c),
    );
  }
}

// ── Section parsers ───────────────────────────────────────────────────────────

CGMState _parseCgm(Map<String, dynamic> g) {
  final rawValue = g['current_value'] as int?;
  final trendStr = g['trend'] as String?;
  final tirRaw = g['time_in_range_24h'] as double?;
  final lastUpdatedStr = g['last_updated'] as String?;

  return CGMState(
    currentGlucose: rawValue ?? 0,
    trend: parseGlucoseTrend(trendStr),
    lastUpdatedMinutesAgo: _minutesAgo(lastUpdatedStr),
    currentStatus: parseGlucoseStatus(rawValue),
    // TIR is 0.0–1.0 from backend; display expects 0–100
    timeInRange24h: tirRaw != null ? tirRaw * 100 : 0.0,
    averageGlucose28Days: 0.0,
    timeInRangeBreakdown: TIRBreakdown(below: 0.0, target: 0.0, above: 0.0),
    last24Hours: const [],
  );
}

NutritionState _parseNutrition(Map<String, dynamic> n) {
  final eaten = (n['calories_eaten'] as num?)?.toInt() ?? 0;
  final target = (n['calorie_target'] as num?)?.toInt() ?? 2200;
  return NutritionState(
    caloriesEaten: eaten,
    calorieTarget: target,
    carbsEaten: (n['carbs_g'] as num?)?.toDouble() ?? 0.0,
    proteinEaten: (n['protein_g'] as num?)?.toDouble() ?? 0.0,
    fatEaten: (n['fat_g'] as num?)?.toDouble() ?? 0.0,
    caloriesRemaining: target - eaten,
    todaysMeals: const [],
  );
}

ActivityState _parseActivity(Map<String, dynamic> a) {
  return ActivityState(
    stepsToday: (a['steps_today'] as num?)?.toInt() ?? 0,
    stepTarget: (a['steps_goal'] as num?)?.toInt() ?? 10000,
    caloriesBurned: (a['calories_burned'] as num?)?.toInt() ?? 0,
    activeMinutes: (a['active_minutes'] as num?)?.toInt() ?? 0,
    heartRate: 0,
    stepHistory: const [],
  );
}

List<Challenge> _parseChallenges(List<dynamic> raw) {
  return raw.map((c) {
    final map = c as Map<String, dynamic>;
    return Challenge(
      title: map['title'] as String? ?? '',
      xpReward: (map['xp_reward'] as num?)?.toInt() ?? 0,
      isCompleted: map['is_completed'] as bool? ?? false,
      category: _parseCategory(map['category'] as String?),
    );
  }).toList();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Public (not `_`-prefixed): shared with the /ws/app/stream live handler in
// glucose_provider.dart, which needs to classify a pushed glucose.reading
// frame identically to how a REST-fetched dashboard reading is classified —
// otherwise the live badge and the REST-derived value could disagree.
GlucoseTrend parseGlucoseTrend(String? trend) {
  switch (trend) {
    case 'RISING_FAST':
      return GlucoseTrend.rapidlyRising;
    case 'RISING':
      return GlucoseTrend.rising;
    case 'FALLING':
      return GlucoseTrend.falling;
    case 'FALLING_FAST':
      return GlucoseTrend.rapidlyFalling;
    default:
      return GlucoseTrend.stable;
  }
}

GlucoseStatus parseGlucoseStatus(int? value) {
  if (value == null) return GlucoseStatus.inRange;
  if (value < 70) return GlucoseStatus.low;
  if (value > 250) return GlucoseStatus.veryHigh;
  if (value > 180) return GlucoseStatus.high;
  return GlucoseStatus.inRange;
}

ChallengeCategory _parseCategory(String? cat) {
  switch (cat) {
    case 'nutrition':
      return ChallengeCategory.nutrition;
    case 'activity':
      return ChallengeCategory.activity;
    case 'diabetes':
      return ChallengeCategory.diabetes;
    case 'wellness':
      return ChallengeCategory.wellness;
    default:
      return ChallengeCategory.nutrition;
  }
}

int _minutesAgo(String? isoString) {
  if (isoString == null) return 0;
  try {
    final t = DateTime.parse(isoString);
    return DateTime.now().difference(t).inMinutes.abs();
  } catch (_) {
    return 0;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

class DashboardNotifier extends AutoDisposeAsyncNotifier<DashboardData> {
  @override
  FutureOr<DashboardData> build() => _fetch();

  Future<DashboardData> _fetch() async {
    final response = await ref.read(apiClientProvider).get('/dashboard');
    return DashboardData.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

final dashboardProvider =
    AsyncNotifierProvider.autoDispose<DashboardNotifier, DashboardData>(
  DashboardNotifier.new,
);
