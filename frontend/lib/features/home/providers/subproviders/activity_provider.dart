import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/models.dart';
import 'dashboard_provider.dart';

// ── Activity provider — derived from dashboardProvider ────────────────────────
// Activity data (steps, calories burned) will be synced from the phone's
// health package in a future release. For now the backend returns zeros
// and the phone-side sync is a no-op.

class ActivityNotifier extends AutoDisposeAsyncNotifier<ActivityState> {
  @override
  FutureOr<ActivityState> build() async {
    final dashboard = await ref.watch(dashboardProvider.future);
    return dashboard.activity;
  }

  // TODO: implement HealthKit / Google Fit sync and POST to /activity/sync
  Future<void> syncWithHealth() async {}
}

final activityProvider =
    AsyncNotifierProvider.autoDispose<ActivityNotifier, ActivityState>(
  ActivityNotifier.new,
);
