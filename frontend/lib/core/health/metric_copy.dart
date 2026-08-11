// Per-metric "why is this empty, and what fixes it" copy
// (docs/health-data-setup.md §2) — the single source of truth for every
// place a health metric card can be empty, so each one explains *that
// specific metric's* real requirement instead of one generic "connect a
// device" message. A generic message is actively wrong for e.g. HRV: no
// permission grant on its own will ever make HRV appear, because a phone
// alone cannot produce it — see §1 of the doc ("if no source app is
// writing a given metric... granting Mytr.AI every permission in the
// world still shows 'no data'").

enum MetricRequirement {
  /// Works from the phone's own sensors once Health Connect/HealthKit
  /// permission is granted — no wearable needed. Steps, active calories.
  permissionOnly,

  /// Needs a wearable with a continuous PPG sensor, but not necessarily
  /// overnight wear. Current heart rate.
  wearableGeneral,

  /// Needs a wearable worn overnight or at rest for several hours — the
  /// phone genuinely cannot provide these regardless of permissions.
  /// Resting heart rate, HRV, sleep stages.
  wearableOvernight,

  /// No data source exists anywhere in the pipeline yet. Not a "go
  /// connect something" gap — nothing the user does fixes this today, so
  /// this must never carry a call-to-action that implies otherwise.
  notTrackedYet,
}

class MetricInfo {
  final String label;
  final MetricRequirement requirement;
  final String emptyMessage;

  /// Null only for [MetricRequirement.notTrackedYet] — every other
  /// requirement has a real action that can actually produce this metric.
  final String? ctaLabel;

  const MetricInfo({
    required this.label,
    required this.requirement,
    required this.emptyMessage,
    this.ctaLabel,
  });
}

const stepsMetric = MetricInfo(
  label: 'Steps',
  requirement: MetricRequirement.permissionOnly,
  emptyMessage: 'Grant Health permission to see your steps.',
  ctaLabel: 'Grant permission',
);

const caloriesMetric = MetricInfo(
  label: 'Calories',
  requirement: MetricRequirement.permissionOnly,
  emptyMessage: 'Grant Health permission to see active calories.',
  ctaLabel: 'Grant permission',
);

const heartRateMetric = MetricInfo(
  label: 'Heart Rate',
  requirement: MetricRequirement.wearableGeneral,
  emptyMessage: 'Needs a watch or band with a heart-rate sensor.',
  ctaLabel: 'Connect a wearable',
);

const restingHeartRateMetric = MetricInfo(
  label: 'Resting HR',
  requirement: MetricRequirement.wearableOvernight,
  emptyMessage: 'Needs a wearable worn for several hours to compute a resting rate.',
  ctaLabel: 'Connect a wearable',
);

const hrvMetric = MetricInfo(
  label: 'HRV',
  requirement: MetricRequirement.wearableOvernight,
  emptyMessage: 'Needs a wearable worn overnight — HRV is computed while you sleep.',
  ctaLabel: 'Connect a wearable',
);

const sleepMetric = MetricInfo(
  label: 'Sleep',
  requirement: MetricRequirement.wearableOvernight,
  emptyMessage: 'Needs a wearable worn overnight to track your sleep.',
  ctaLabel: 'Connect a wearable',
);

// Deliberately no CTA: there is no active_minutes column, no rollup, no
// path to this ever populating — a "Connect a wearable" button here would
// promise a fix that doesn't exist. See backend/app/api/dashboard.py.
const activeMinutesMetric = MetricInfo(
  label: 'Active Minutes',
  requirement: MetricRequirement.notTrackedYet,
  emptyMessage: 'Not tracked yet.',
  ctaLabel: null,
);
