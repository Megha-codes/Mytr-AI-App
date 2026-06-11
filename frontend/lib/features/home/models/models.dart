import 'package:hive/hive.dart';

part 'models.g.dart';

@HiveType(typeId: 0)
enum UserType { 
  @HiveField(0) type1, 
  @HiveField(1) type2, 
  @HiveField(2) fitness 
}

@HiveType(typeId: 1)
class Achievement {
  @HiveField(0) final String id;
  @HiveField(1) final String title;
  @HiveField(2) final String icon;
  @HiveField(3) final String category;
  @HiveField(4) final bool isUnlocked;

  Achievement({
    required this.id,
    required this.title,
    required this.icon,
    required this.category,
    this.isUnlocked = false,
  });
}

@HiveType(typeId: 2)
class UserProfile {
  @HiveField(0) final String displayName;
  @HiveField(1) final String? avatarImageUrl;
  @HiveField(2) final UserType userType;
  @HiveField(3) final int currentLevel;
  @HiveField(4) final String levelTitle;
  @HiveField(5) final int currentXP;
  @HiveField(6) final int xpToNextLevel;
  @HiveField(7) final double startingWeight;
  @HiveField(8) final double weightGoal;
  @HiveField(9) final String primaryGoal;
  @HiveField(10) final List<Achievement> recentAchievements;
  // Not persisted to Hive — populated from API response only.
  final double? heightCm;

  UserProfile({
    required this.displayName,
    this.avatarImageUrl,
    required this.userType,
    this.currentLevel = 1,
    this.levelTitle = 'Novice',
    this.currentXP = 0,
    this.xpToNextLevel = 1000,
    required this.startingWeight,
    required this.weightGoal,
    required this.primaryGoal,
    required this.recentAchievements,
    this.heightCm,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      displayName: json['display_name'] ?? 'User',
      avatarImageUrl: json['avatar_url'],
      userType: UserType.values.byName(json['user_type']?.toString().toLowerCase() ?? 'type1'),
      currentLevel: json['current_level'] ?? 1,
      levelTitle: json['level_title'] ?? 'Novice',
      currentXP: json['current_xp'] ?? 0,
      xpToNextLevel: json['xp_to_next_level'] ?? 1000,
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      startingWeight: (json['starting_weight'] as num?)?.toDouble() ?? 0.0,
      weightGoal: (json['weight_goal'] as num?)?.toDouble() ?? 0.0,
      primaryGoal: json['primary_goal'] ?? '',
      recentAchievements: (json['recent_achievements'] as List?)
          ?.map((a) => Achievement(
                id: a['id'],
                title: a['title'],
                icon: a['icon'],
                category: a['category'],
                isUnlocked: a['is_unlocked'] ?? false,
              ))
          .toList() ?? [],
    );
  }
}

@HiveType(typeId: 3)
enum GlucoseTrend { 
  @HiveField(0) rapidlyRising, 
  @HiveField(1) rising, 
  @HiveField(2) stable, 
  @HiveField(3) falling, 
  @HiveField(4) rapidlyFalling 
}

@HiveType(typeId: 4)
enum GlucoseStatus { 
  @HiveField(0) low, 
  @HiveField(1) inRange, 
  @HiveField(2) high, 
  @HiveField(3) veryHigh 
}

@HiveType(typeId: 5)
class GlucoseReading {
  @HiveField(0) final DateTime timestamp;
  @HiveField(1) final double value;
  @HiveField(2) final GlucoseTrend trend;
  @HiveField(3) final GlucoseStatus status;

  GlucoseReading({
    required this.timestamp,
    required this.value,
    this.trend = GlucoseTrend.stable,
    this.status = GlucoseStatus.inRange,
  });

  factory GlucoseReading.fromJson(Map<String, dynamic> json) {
    return GlucoseReading(
      timestamp: DateTime.parse(json['timestamp']),
      value: (json['value'] as num).toDouble(),
      trend: GlucoseTrend.values.byName(json['trend'] ?? 'stable'),
      status: GlucoseStatus.values.byName(json['status'] ?? 'inRange'),
    );
  }
}

@HiveType(typeId: 6)
class ActivitySummary {
  @HiveField(0) final int steps;
  @HiveField(1) final int calories;
  @HiveField(2) final int activeMinutes;
  @HiveField(3) final int heartRate;

  ActivitySummary({
    required this.steps,
    required this.calories,
    required this.activeMinutes,
    required this.heartRate,
  });

  factory ActivitySummary.fromJson(Map<String, dynamic> json) {
    return ActivitySummary(
      steps: json['steps'] ?? 0,
      calories: json['calories'] ?? 0,
      activeMinutes: json['active_minutes'] ?? 0,
      heartRate: json['heart_rate'] ?? 0,
    );
  }
}

@HiveType(typeId: 7)
class SleepData {
  @HiveField(0) final double totalHours;
  @HiveField(1) final List<SleepStage> stages;

  SleepData({required this.totalHours, required this.stages});
}

@HiveType(typeId: 8)
class SleepStage {
  @HiveField(0) final SleepStageType type;
  @HiveField(1) final double hours;

  SleepStage({required this.type, required this.hours});
}

@HiveType(typeId: 9)
enum SleepStageType { 
  @HiveField(0) awake, 
  @HiveField(1) light, 
  @HiveField(2) deep, 
  @HiveField(3) rem 
}

@HiveType(typeId: 10)
class CoachInsight {
  @HiveField(0) final String title;
  @HiveField(1) final String description;
  @HiveField(2) final String category;
  @HiveField(3) final double estimatedSavingUnits;
  @HiveField(4) final double progress;

  CoachInsight({
    required this.title,
    required this.description,
    required this.category,
    this.estimatedSavingUnits = 0.0,
    this.progress = 0.0,
  });
}

@HiveType(typeId: 11)
class WeightEntry {
  @HiveField(0) final DateTime timestamp;
  @HiveField(1) final double weight;

  WeightEntry({required this.timestamp, required this.weight});
}

@HiveType(typeId: 12)
class NutritionSummary {
  @HiveField(0) final int calories;
  @HiveField(1) final int carbsG;
  @HiveField(2) final int proteinG;
  @HiveField(3) final int fatG;

  NutritionSummary({
    required this.calories,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
  });
}

@HiveType(typeId: 14)
class LoggedMeal {
  @HiveField(0) final String id;
  @HiveField(1) final String name;
  @HiveField(2) final DateTime timestamp;
  @HiveField(3) final int calories;
  @HiveField(4) final int carbsG;
  @HiveField(5) final int proteinG;
  @HiveField(6) final int fatG;
  @HiveField(7) final double glycaemicLoad;
  @HiveField(8) final int estimatedRiseMinutes;

  LoggedMeal({
    required this.id,
    required this.name,
    required this.timestamp,
    required this.calories,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
    this.glycaemicLoad = 0.0,
    this.estimatedRiseMinutes = 0,
  });
}

@HiveType(typeId: 15)
class GlucosePoint {
  @HiveField(0) final DateTime time;
  @HiveField(1) final double value;

  GlucosePoint({required this.time, required this.value});
}

@HiveType(typeId: 16)
class TIRBreakdown {
  @HiveField(0) final double below;
  @HiveField(1) final double target;
  @HiveField(2) final double above;

  TIRBreakdown({required this.below, required this.target, required this.above});
}

@HiveType(typeId: 17)
class CGMState {
  @HiveField(0) final int currentGlucose;
  @HiveField(1) final GlucoseTrend trend;
  @HiveField(2) final int lastUpdatedMinutesAgo;
  @HiveField(3) final GlucoseStatus currentStatus;
  @HiveField(4) final List<GlucosePoint> last24Hours;
  @HiveField(5) final double timeInRange24h;
  @HiveField(6) final double averageGlucose28Days;
  @HiveField(7) final TIRBreakdown timeInRangeBreakdown;

  CGMState({
    required this.currentGlucose,
    required this.trend,
    required this.lastUpdatedMinutesAgo,
    required this.currentStatus,
    required this.last24Hours,
    required this.timeInRange24h,
    required this.averageGlucose28Days,
    required this.timeInRangeBreakdown,
  });

  String get trendArrow => switch (trend) {
    GlucoseTrend.rapidlyRising => '↑↑',
    GlucoseTrend.rising => '↑',
    GlucoseTrend.stable => '→',
    GlucoseTrend.falling => '↓',
    GlucoseTrend.rapidlyFalling => '↓↓',
  };
}

@HiveType(typeId: 18)
class NutritionState {
  @HiveField(0) final int caloriesEaten;
  @HiveField(1) final int calorieTarget;
  @HiveField(2) final double carbsEaten;
  @HiveField(3) final double proteinEaten;
  @HiveField(4) final double fatEaten;
  @HiveField(5) final int caloriesRemaining;
  @HiveField(6) final List<LoggedMeal> todaysMeals;

  NutritionState({
    required this.caloriesEaten,
    required this.calorieTarget,
    required this.carbsEaten,
    required this.proteinEaten,
    required this.fatEaten,
    required this.caloriesRemaining,
    required this.todaysMeals,
  });

  factory NutritionState.fromJson(Map<String, dynamic> json) {
    return NutritionState(
      caloriesEaten: json['calories_eaten'] ?? 0,
      calorieTarget: json['calorie_target'] ?? 2000,
      carbsEaten: (json['carbs_eaten'] as num?)?.toDouble() ?? 0.0,
      proteinEaten: (json['protein_eaten'] as num?)?.toDouble() ?? 0.0,
      fatEaten: (json['fat_eaten'] as num?)?.toDouble() ?? 0.0,
      caloriesRemaining: json['calories_remaining'] ?? 0,
      todaysMeals: (json['todays_meals'] as List?)
          ?.map((m) => LoggedMeal(
                id: m['id'],
                name: m['name'],
                timestamp: DateTime.parse(m['timestamp']),
                calories: m['calories'],
                carbsG: m['carbs_g'],
                proteinG: m['protein_g'],
                fatG: m['fat_g'],
              ))
          .toList() ?? [],
    );
  }
}

@HiveType(typeId: 19)
class ActivityState {
  @HiveField(0) final int stepsToday;
  @HiveField(1) final int stepTarget;
  @HiveField(2) final int caloriesBurned;
  @HiveField(3) final int activeMinutes;
  @HiveField(4) final int heartRate;
  @HiveField(5) final List<DailyValue> stepHistory;

  ActivityState({
    required this.stepsToday,
    required this.stepTarget,
    required this.caloriesBurned,
    required this.activeMinutes,
    required this.heartRate,
    required this.stepHistory,
  });

  factory ActivityState.fromJson(Map<String, dynamic> json) {
    return ActivityState(
      stepsToday: json['steps_today'] ?? 0,
      stepTarget: json['step_target'] ?? 10000,
      caloriesBurned: json['calories_burned'] ?? 0,
      activeMinutes: json['active_minutes'] ?? 0,
      heartRate: json['heart_rate'] ?? 0,
      stepHistory: [], // Map from history in real app
    );
  }
}

@HiveType(typeId: 20)
class CoachState {
  @HiveField(0) final String morningBriefing;
  @HiveField(1) final List<CoachInsight> insights;
  @HiveField(2) final String todayFocus;
  @HiveField(3) final List<CoachInsight> targets;

  CoachState({
    required this.morningBriefing,
    required this.insights,
    this.todayFocus = '',
    this.targets = const [],
  });

  factory CoachState.fromJson(Map<String, dynamic> json) {
    return CoachState(
      morningBriefing: json['morning_briefing'] ?? '',
      todayFocus: json['today_focus'] ?? '',
      insights: (json['insights'] as List?)
          ?.map((i) => CoachInsight(
                title: i['title'],
                description: i['description'],
                category: i['category'],
                estimatedSavingUnits: (i['estimated_saving_units'] as num?)?.toDouble() ?? 0.0,
                progress: (i['progress'] as num?)?.toDouble() ?? 0.0,
              ))
          .toList() ?? [],
      targets: (json['targets'] as List?)
          ?.map((i) => CoachInsight(
                title: i['title'],
                description: i['description'],
                category: i['category'],
                progress: (i['progress'] as num?)?.toDouble() ?? 0.0,
              ))
          .toList() ?? [],
    );
  }
}

@HiveType(typeId: 21)
enum SensorStatus { 
  @HiveField(0) active, 
  @HiveField(1) warmingUp, 
  @HiveField(2) disconnected, 
  @HiveField(3) expired 
}

@HiveType(typeId: 22)
class CGMDevice {
  @HiveField(0) final String id;
  @HiveField(1) final String name;
  @HiveField(2) final SensorStatus status;
  @HiveField(3) final int daysRemaining;

  CGMDevice({
    required this.id,
    required this.name,
    required this.status,
    required this.daysRemaining,
  });
}

@HiveType(typeId: 23)
class DailyValue {
  @HiveField(0) final String day;
  @HiveField(1) final double value;
  
  DailyValue({required this.day, required this.value});
}

@HiveType(typeId: 24)
enum ChallengeCategory { 
  @HiveField(0) nutrition, 
  @HiveField(1) activity, 
  @HiveField(2) diabetes, 
  @HiveField(3) wellness 
}

@HiveType(typeId: 25)
class Challenge {
  @HiveField(0) final String title;
  @HiveField(1) final int xpReward;
  @HiveField(2) final bool isCompleted;
  @HiveField(3) final ChallengeCategory category;

  Challenge({
    required this.title,
    required this.xpReward,
    required this.isCompleted,
    required this.category,
  });
}
