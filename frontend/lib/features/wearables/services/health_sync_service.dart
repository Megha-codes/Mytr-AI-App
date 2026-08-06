import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/health_sample_mapper.dart';
import '../../../core/services/health_service.dart';
import '../../home/providers/subproviders/dashboard_provider.dart';
import '../../home/providers/subproviders/health_daily_provider.dart';
import '../providers/wearable_provider.dart';
import 'google_health_service.dart';

class HealthSyncOutcome {
  final int sampled;
  final int accepted;
  final int duplicates;
  final String? error;

  const HealthSyncOutcome({this.sampled = 0, this.accepted = 0, this.duplicates = 0, this.error});

  bool get ok => error == null;
}

/// The single sync path from device health data to the backend
/// (architecture-v3.md §2.5): repoints what used to be the dead
/// `ActivityNotifier.syncWithHealth()` → lossy `/activity/sync` onto
/// `POST /health/samples`, with per-sample external_ids so calling this
/// repeatedly (on foreground, on pull-to-refresh, right after connecting)
/// is safe — the backend dedups, it doesn't double-count.
class HealthSyncService {
  HealthSyncService(this._ref);
  final Ref _ref;

  /// How far back to look on each sync. Deliberately wider than "since
  /// midnight": a sleep session that started before midnight (e.g. fell
  /// asleep at 11pm) would otherwise be half-missed. Overlap with the
  /// previous sync is fine — every sample carries a stable external_id, so
  /// re-sending it is a no-op on the backend.
  static const _lookback = Duration(hours: 36);

  Future<HealthSyncOutcome> sync() async {
    final wearables = _ref.read(wearableProvider).valueOrNull;
    if (wearables == null) return const HealthSyncOutcome();

    final samples = <HealthSampleDraft>[];

    if (wearables.healthConnected) {
      // Native HealthKit/Health Connect is authoritative when connected —
      // covers steps/calories/heart_rate AND the metrics Fitbit-via-Google-
      // Health can't provide at all (resting HR, HRV, sleep). Deliberately
      // NOT also pulling the overlapping fields from Google Health below:
      // summing the same steps from two sources would double-count them.
      try {
        final points = await HealthService.instance.fetchRecentSamples(since: _lookback);
        for (final point in points) {
          final draft = mapHealthDataPoint(point);
          if (draft != null) samples.add(draft);
        }
        _ref.read(lastSyncedSleepStagesProvider.notifier).state = deriveSleepStages(points);
      } catch (_) {
        // Leave whatever stage breakdown we already had rather than
        // clearing it on a transient read failure.
      }
    } else if (wearables.googleHealthConnected) {
      // Fitbit via Google Health API only ever gives us a same-day
      // aggregate, not per-sample points — no HRV/RHR/sleep from this path.
      try {
        samples.addAll(await _fitbitSamples());
      } catch (_) {}
    }

    if (samples.isEmpty) return const HealthSyncOutcome();

    try {
      int accepted = 0;
      int duplicates = 0;
      for (final batch in _chunked(samples, 1000)) {
        final response = await _ref.read(apiClientProvider).post('/health/samples', data: {
          'samples': batch.map((s) => s.toJson()).toList(),
        });
        final data = response.data as Map<String, dynamic>;
        accepted += (data['accepted'] as num?)?.toInt() ?? 0;
        duplicates += (data['duplicates'] as num?)?.toInt() ?? 0;
      }

      // POST /health/samples also recomputes the activity_logs projection
      // server-side, so refreshing dashboardProvider is what makes
      // steps/calories/heart_rate show up — same mechanism a manual glucose
      // entry already uses to refresh the glucose card.
      _ref.invalidate(dashboardProvider);
      _ref.invalidate(healthDailyProvider);

      return HealthSyncOutcome(sampled: samples.length, accepted: accepted, duplicates: duplicates);
    } on DioException catch (e) {
      final message = e.response?.data?['detail']?.toString() ?? 'Health sync failed.';
      return HealthSyncOutcome(sampled: samples.length, error: message);
    } catch (_) {
      // Anything else (malformed response body, etc.) — this runs
      // unattended on app foreground, so it must never throw past here.
      return HealthSyncOutcome(sampled: samples.length, error: 'Health sync failed.');
    }
  }

  Future<List<HealthSampleDraft>> _fitbitSamples() async {
    final data = await GoogleHealthService.instance.fetchToday();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final day = _dateKey(now);
    const source = 'GOOGLE_HEALTH_FITBIT';

    final drafts = <HealthSampleDraft>[];
    if (data.steps > 0) {
      drafts.add(HealthSampleDraft(
        metric: 'steps', value: data.steps.toDouble(), unit: 'count',
        startedAt: midnight, endedAt: now, source: source,
        externalId: 'fitbit-$day-steps',
      ));
    }
    if (data.caloriesOut > 0) {
      drafts.add(HealthSampleDraft(
        metric: 'active_energy_kcal', value: data.caloriesOut.toDouble(), unit: 'kcal',
        startedAt: midnight, endedAt: now, source: source,
        externalId: 'fitbit-$day-active_energy_kcal',
      ));
    }
    if (data.heartRate > 0) {
      drafts.add(HealthSampleDraft(
        metric: 'heart_rate', value: data.heartRate.toDouble(), unit: 'bpm',
        startedAt: midnight, endedAt: now, source: source,
        externalId: 'fitbit-$day-heart_rate',
      ));
    }
    return drafts;
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Iterable<List<T>> _chunked<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }
}

final healthSyncServiceProvider = Provider<HealthSyncService>((ref) => HealthSyncService(ref));
