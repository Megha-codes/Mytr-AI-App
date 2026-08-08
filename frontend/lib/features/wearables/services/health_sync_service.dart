import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/health_sample_mapper.dart';
import '../../../core/services/health_service.dart';
import '../../home/providers/subproviders/dashboard_provider.dart';
import '../../home/providers/subproviders/health_daily_provider.dart';
import '../providers/wearable_provider.dart';

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
///
/// One source only: native HealthKit/Health Connect via [HealthService].
/// There used to be a second, OAuth-based Fitbit-via-Google-Health path
/// here — removed. Fitbit's own Android app writes into Health Connect
/// directly, so connecting Health Connect already covers Fitbit for
/// anyone syncing that way, without a second login.
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
    if (wearables == null || !wearables.healthConnected) {
      return const HealthSyncOutcome();
    }

    final samples = <HealthSampleDraft>[];
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

  Iterable<List<T>> _chunked<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }
}

final healthSyncServiceProvider = Provider<HealthSyncService>((ref) => HealthSyncService(ref));
