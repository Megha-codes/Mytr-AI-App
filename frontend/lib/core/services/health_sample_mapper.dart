import 'package:health/health.dart';
import '../../features/home/models/models.dart';

/// Mirrors backend `HealthSampleIn` (backend/app/schemas/health.py) exactly:
/// metric/value/unit/started_at/ended_at/source/external_id. Field names
/// here are the Dart-side ones; [toJson] converts to the snake_case the
/// backend expects.
class HealthSampleDraft {
  final String metric;
  final double value;
  final String unit;
  final DateTime startedAt;
  final DateTime endedAt;
  final String source;
  final String? externalId;

  const HealthSampleDraft({
    required this.metric,
    required this.value,
    required this.unit,
    required this.startedAt,
    required this.endedAt,
    required this.source,
    this.externalId,
  });

  Map<String, dynamic> toJson() => {
        'metric': metric,
        'value': value,
        'unit': unit,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
        'source': source,
        if (externalId != null) 'external_id': externalId,
      };
}

/// backend/app/services/health/daily_rollup.py's _AGGREGATION only knows
/// how to sum/average/last these exact metric strings — anything else
/// silently falls back to "average", which is wrong for a cumulative value
/// like steps. Keep this in sync with the backend dict.
const _metricForType = {
  HealthDataType.STEPS: 'steps',
  HealthDataType.ACTIVE_ENERGY_BURNED: 'active_energy_kcal',
  HealthDataType.HEART_RATE: 'heart_rate',
  HealthDataType.RESTING_HEART_RATE: 'resting_heart_rate',
  HealthDataType.HEART_RATE_VARIABILITY_SDNN: 'hrv',
  HealthDataType.HEART_RATE_VARIABILITY_RMSSD: 'hrv',
  HealthDataType.SLEEP_ASLEEP: 'sleep_minutes',
  HealthDataType.SLEEP_DEEP: 'sleep_minutes',
  HealthDataType.SLEEP_LIGHT: 'sleep_minutes',
  HealthDataType.SLEEP_REM: 'sleep_minutes',
  // SLEEP_AWAKE deliberately absent — it's time NOT asleep, so it must not
  // be summed into "sleep_minutes" (see deriveSleepStages, which does use
  // it, for the local stage-breakdown display instead).
};

const _unitForMetric = {
  'steps': 'count',
  'active_energy_kcal': 'kcal',
  'heart_rate': 'bpm',
  'resting_heart_rate': 'bpm',
  'hrv': 'ms',
  'sleep_minutes': 'min',
};

String sourceForPlatform(HealthPlatformType platform) => switch (platform) {
      HealthPlatformType.appleHealth => 'APPLE_HEALTH',
      HealthPlatformType.googleHealthConnect => 'HEALTH_CONNECT',
    };

/// Returns null for point types this app doesn't ingest to the backend
/// (currently just SLEEP_AWAKE — see [_metricForType]).
HealthSampleDraft? mapHealthDataPoint(HealthDataPoint point) {
  final metric = _metricForType[point.type];
  if (metric == null) return null;

  final value = point.value;
  if (value is! NumericHealthValue) return null;

  return HealthSampleDraft(
    metric: metric,
    value: value.numericValue.toDouble(),
    unit: _unitForMetric[metric] ?? point.unit.name,
    startedAt: point.dateFrom,
    endedAt: point.dateTo,
    source: sourceForPlatform(point.sourcePlatform),
    // uuid is stable per data point on both HealthKit and Health Connect —
    // this is what makes re-sending the same day's data safe (backend
    // dedups on (user, source, metric, external_id)). Some platforms/older
    // OS versions can return an empty uuid for a handful of point types; in
    // that rare case we omit external_id rather than send a fake one — the
    // sample still gets ingested, just without dedup protection for that
    // one point.
    externalId: point.uuid.isNotEmpty ? point.uuid : null,
  );
}

const _sleepStageTypeForHealthType = {
  HealthDataType.SLEEP_AWAKE: SleepStageType.awake,
  HealthDataType.SLEEP_LIGHT: SleepStageType.light,
  HealthDataType.SLEEP_DEEP: SleepStageType.deep,
  HealthDataType.SLEEP_REM: SleepStageType.rem,
  // HealthKit reports plain "asleep, stage unspecified" on older data /
  // sources that don't do stage detection. There's no matching bucket in
  // this app's 4-stage model (awake/light/deep/rem) — approximating it as
  // "light" rather than dropping it, so the total still adds up to
  // something close to real sleep time. This is a deliberate simplification
  // worth knowing about if the stage breakdown ever needs to be precise.
  HealthDataType.SLEEP_ASLEEP: SleepStageType.light,
};

/// Local-only — the backend has no per-stage storage (§1.4's health_metrics
/// only has one "sleep_minutes" metric), so this reflects whatever was just
/// fetched from HealthKit/Health Connect in the current sync pass, not a
/// durable server-side value. Only meaningful for a "last night" window;
/// pass the SLEEP_* subset of a fetch covering roughly the last 24-36h.
List<SleepStage> deriveSleepStages(List<HealthDataPoint> points) {
  final totals = <SleepStageType, double>{};
  for (final point in points) {
    final stageType = _sleepStageTypeForHealthType[point.type];
    if (stageType == null) continue;
    final value = point.value;
    if (value is! NumericHealthValue) continue;
    final minutes = value.numericValue.toDouble();
    totals[stageType] = (totals[stageType] ?? 0) + minutes;
  }
  if (totals.isEmpty) return [];
  return totals.entries
      .map((e) => SleepStage(type: e.key, hours: e.value / 60))
      .toList();
}
