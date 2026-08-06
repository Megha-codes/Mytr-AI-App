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

  // Requested outside of any per-platform branch: supported by both
  // HealthKit and Health Connect with the same enum value.
  static const _commonTypes = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    // Sleep stages: these five names exist in both platforms' supported-type
    // lists (the `health` package's dataTypeKeysIOS/dataTypeKeysAndroid).
    // Deliberately NOT requested: HealthKit-only SLEEP_IN_BED, and Health
    // Connect-only SLEEP_AWAKE_IN_BED/SLEEP_OUT_OF_BED/SLEEP_SESSION/
    // SLEEP_UNKNOWN — all bookkeeping/container categories, not sleep time
    // itself, and requesting a type absent from a platform's supported list
    // risks the whole authorization call being rejected rather than just
    // that one type being ignored.
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
  ];

  /// HRV is the one metric where the two platforms don't just gate the same
  /// type — they measure genuinely different statistics. HealthKit reports
  /// SDNN (standard deviation of NN intervals); Health Connect reports
  /// RMSSD (root mean square of successive differences). These are NOT the
  /// same number for the same underlying heartbeat data, and there is no
  /// clean conversion between them. Both get ingested under one backend
  /// "hrv" metric for now (per-platform, so a single device only ever
  /// contributes one or the other) — this is a known simplification: a user
  /// who switches from iPhone to Android would see a discontinuity in their
  /// HRV trend that isn't a real physiological change. Flagging it here
  /// rather than silently treating them as equivalent.
  static HealthDataType get _hrvType => Platform.isIOS
      ? HealthDataType.HEART_RATE_VARIABILITY_SDNN
      : HealthDataType.HEART_RATE_VARIABILITY_RMSSD;

  // Every call site below already checks _supported before touching _types,
  // but guard here too rather than depend on that staying true forever —
  // Platform.isIOS throws on web, and _hrvType has no other guard of its own.
  static List<HealthDataType> get _types =>
      _supported ? [..._commonTypes, _hrvType] : _commonTypes;

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

  /// Raw, unaggregated data points for everything in [_types] (now including
  /// HRV, resting heart rate, and sleep) since [since]. Unlike [fetchToday],
  /// this is not summarized client-side — each point carries its own
  /// [HealthDataPoint.uuid], which the caller uses as a per-sample
  /// idempotency key when posting to the backend, so the backend's own
  /// dedup/rollup does the aggregation instead of this client guessing at it.
  Future<List<HealthDataPoint>> fetchRecentSamples({required Duration since}) async {
    if (!_supported) return [];
    final now = DateTime.now();
    try {
      return await _health.getHealthDataFromTypes(
        startTime: now.subtract(since),
        endTime: now,
        types: _types,
      );
    } catch (_) {
      return [];
    }
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
