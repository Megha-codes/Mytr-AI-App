import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/models.dart';
import 'dashboard_provider.dart';

// Steps/calories/heart_rate are derived from dashboardProvider, same as
// cgmProvider — both ultimately trace back to activity_logs, which
// POST /health/samples now keeps current via the server-side projection
// recompute (architecture-v3.md §4.2). The sync trigger itself lives in
// HealthSyncService (features/wearables/services/health_sync_service.dart)
// — this used to be a syncWithHealth() method here that posted straight to
// the lossy /activity/sync and was never actually called from anywhere;
// removed rather than kept as a second, competing sync path.
class ActivityNotifier extends AutoDisposeAsyncNotifier<ActivityState> {
  @override
  FutureOr<ActivityState> build() async {
    final dashboard = await ref.watch(dashboardProvider.future);
    return dashboard.activity;
  }
}

final activityProvider =
    AsyncNotifierProvider.autoDispose<ActivityNotifier, ActivityState>(
  ActivityNotifier.new,
);
