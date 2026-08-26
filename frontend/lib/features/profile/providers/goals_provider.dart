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

class GoalsNotifier extends AutoDisposeAsyncNotifier<Goals> {
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

  /// Wipes this user's goals from disk AND resets in-memory state, so the
  /// next signed-in user (same phone, same process — logout doesn't restart
  /// the app) never inherits them. This storage is a private
  /// FlutterSecureStorage instance under its own key ('user_goals'),
  /// entirely separate from AuthStorageService — clearAll() on that service
  /// never reaches it, which is exactly how this leaked across users before.
  /// Called from AuthNotifier.logout()/logoutAllDevices()/deleteAccount().
  Future<void> clear() async {
    state = const AsyncData(Goals());
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

final goalsProvider =
    AsyncNotifierProvider.autoDispose<GoalsNotifier, Goals>(GoalsNotifier.new);
