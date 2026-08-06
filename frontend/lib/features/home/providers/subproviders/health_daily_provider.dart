import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../models/models.dart';

/// Mirrors backend GET /health/daily (backend/app/api/health.py,
/// HealthDailyResponse, response_model_exclude_none=True): every field
/// except [date] is null when there is no data for that metric today —
/// never zero-filled. "0 steps" and "no data" are different facts, and this
/// model preserves that distinction all the way to the UI instead of
/// collapsing it the way ActivityState's dashboard-derived fields do today.
class HealthDailyState {
  final double? steps;
  final double? activeEnergyKcal;
  final double? heartRate;
  final double? restingHeartRate;
  final double? sleepMinutes;
  final double? hrv;
  final DateTime? updatedAt;

  const HealthDailyState({
    this.steps,
    this.activeEnergyKcal,
    this.heartRate,
    this.restingHeartRate,
    this.sleepMinutes,
    this.hrv,
    this.updatedAt,
  });

  bool get hasAnyData =>
      steps != null ||
      activeEnergyKcal != null ||
      heartRate != null ||
      restingHeartRate != null ||
      sleepMinutes != null ||
      hrv != null;

  factory HealthDailyState.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic v) => (v as num?)?.toDouble();
    return HealthDailyState(
      steps: asDouble(json['steps']),
      activeEnergyKcal: asDouble(json['active_energy_kcal']),
      heartRate: asDouble(json['heart_rate']),
      restingHeartRate: asDouble(json['resting_heart_rate']),
      sleepMinutes: asDouble(json['sleep_minutes']),
      hrv: asDouble(json['hrv']),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
    );
  }
}

class HealthDailyNotifier extends AutoDisposeAsyncNotifier<HealthDailyState> {
  @override
  Future<HealthDailyState> build() async {
    final response = await ref.read(apiClientProvider).get('/health/daily');
    return HealthDailyState.fromJson(response.data as Map<String, dynamic>);
  }
}

final healthDailyProvider =
    AsyncNotifierProvider.autoDispose<HealthDailyNotifier, HealthDailyState>(
  HealthDailyNotifier.new,
);

/// Sleep stage breakdown has no server-side storage (backend's
/// health_metrics only tracks one "sleep_minutes" total, per §1.4) — this
/// holds whatever HealthSyncService derived from the most recent local
/// fetch, for the sleep stage bar chart to consume directly. It is
/// intentionally NOT persisted or backend-synced: closing and reopening the
/// app without a fresh sync clears it back to empty, at which point the
/// sleep card falls back to showing just the total from [healthDailyProvider]
/// with no stage breakdown.
final lastSyncedSleepStagesProvider = StateProvider<List<SleepStage>>((ref) => const []);
