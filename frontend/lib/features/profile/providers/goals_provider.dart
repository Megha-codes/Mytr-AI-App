import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// User-defined goals. Persisted locally so they survive restarts and work
/// offline. `weightGoalKg` is null until the user sets it.
class Goals {
  final double? weightGoalKg;
  final int dailyStepGoal;
  final int dailyCalorieGoal;

  const Goals({
    this.weightGoalKg,
    this.dailyStepGoal = 10000,
    this.dailyCalorieGoal = 2200,
  });

  bool get isSet => weightGoalKg != null;

  Goals copyWith({
    double? weightGoalKg,
    int? dailyStepGoal,
    int? dailyCalorieGoal,
  }) {
    return Goals(
      weightGoalKg: weightGoalKg ?? this.weightGoalKg,
      dailyStepGoal: dailyStepGoal ?? this.dailyStepGoal,
      dailyCalorieGoal: dailyCalorieGoal ?? this.dailyCalorieGoal,
    );
  }

  Map<String, dynamic> toJson() => {
        'weight_goal_kg': weightGoalKg,
        'daily_step_goal': dailyStepGoal,
        'daily_calorie_goal': dailyCalorieGoal,
      };

  factory Goals.fromJson(Map<String, dynamic> j) => Goals(
        weightGoalKg: (j['weight_goal_kg'] as num?)?.toDouble(),
        dailyStepGoal: (j['daily_step_goal'] as num?)?.toInt() ?? 10000,
        dailyCalorieGoal: (j['daily_calorie_goal'] as num?)?.toInt() ?? 2200,
      );
}

class GoalsNotifier extends AsyncNotifier<Goals> {
  static const _key = 'user_goals';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  @override
  FutureOr<Goals> build() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const Goals();
      return Goals.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Goals();
    }
  }

  Future<void> save(Goals goals) async {
    state = AsyncData(goals);
    try {
      await _storage.write(key: _key, value: jsonEncode(goals.toJson()));
    } catch (_) {
      // Persisting failed; in-memory state still updated for this session.
    }
  }
}

final goalsProvider =
    AsyncNotifierProvider<GoalsNotifier, Goals>(GoalsNotifier.new);
