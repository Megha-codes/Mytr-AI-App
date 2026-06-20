import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import '../../features/home/models/models.dart';

class HealthSyncResult {
  final int steps;
  final int caloriesBurned;
  final int heartRate;
  final List<DailyValue> weeklySteps;

  const HealthSyncResult({
    required this.steps,
    required this.caloriesBurned,
    required this.heartRate,
    required this.weeklySteps,
  });
}

class HealthService {
  HealthService._();
  static final HealthService instance = HealthService._();

  static final _health = Health();

  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.HEART_RATE,
  ];

  static bool get _supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  bool _configured = false;

  Future<void> configure() async {
    if (!_supported || _configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<bool> requestPermissions() async {
    if (!_supported) return false;
    try {
      await configure();
      return await _health.requestAuthorization(_types);
    } catch (_) {
      return false;
    }
  }

  Future<bool> isAuthorized() async {
    if (!_supported) return false;
    try {
      await configure();
      return await _health.hasPermissions(_types) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<HealthSyncResult> fetchToday() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    final steps = await _health.getTotalStepsInInterval(midnight, now) ?? 0;

    final calPoints = await _health.getHealthDataFromTypes(
      startTime: midnight,
      endTime: now,
      types: [HealthDataType.ACTIVE_ENERGY_BURNED],
    );
    final calories = calPoints.fold<double>(0, (sum, p) {
      final v = p.value;
      return v is NumericHealthValue ? sum + v.numericValue.toDouble() : sum;
    });

    final hrPoints = await _health.getHealthDataFromTypes(
      startTime: midnight,
      endTime: now,
      types: [HealthDataType.HEART_RATE],
    );
    int heartRate = 0;
    if (hrPoints.isNotEmpty) {
      final v = hrPoints.last.value;
      if (v is NumericHealthValue) heartRate = v.numericValue.toInt();
    }

    final weekly = await _fetchWeeklySteps(now);

    return HealthSyncResult(
      steps: steps,
      caloriesBurned: calories.toInt(),
      heartRate: heartRate,
      weeklySteps: weekly,
    );
  }

  Future<List<DailyValue>> _fetchWeeklySteps(DateTime now) async {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final result = <DailyValue>[];
    for (int i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      final end = day.add(const Duration(days: 1));
      final count = await _health.getTotalStepsInInterval(day, end) ?? 0;
      result.add(DailyValue(day: labels[day.weekday - 1], value: count.toDouble()));
    }
    return result;
  }
}
