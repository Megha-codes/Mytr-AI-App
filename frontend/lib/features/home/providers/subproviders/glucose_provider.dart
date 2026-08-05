import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/realtime/app_stream_client.dart';
import '../../../../core/services/auth_storage_service.dart';
import '../../models/models.dart';
import 'dashboard_provider.dart';

// ── CGM provider — derived from dashboardProvider, kept live over
// /ws/app/stream (architecture-v3.md §2.6) ────────────────────────────────────

class CGMNotifier extends AutoDisposeAsyncNotifier<CGMState> {
  AppStreamClient? _client;
  StreamSubscription<RealtimeFrame>? _subscription;

  @override
  FutureOr<CGMState> build() async {
    final dashboard = await ref.watch(dashboardProvider.future);

    // build() reruns whenever dashboardProvider changes (e.g. pull-to-refresh,
    // a manual entry invalidating it) — only stand up the socket once per
    // notifier lifetime; AppStreamClient.connect() is itself idempotent too,
    // as a second line of defense.
    if (_client == null) {
      _client = AppStreamClient(getAccessToken: () => AuthStorageService().getAccessToken());
      _subscription = _client!.frames.listen(_onFrame);
      ref.onDispose(() {
        _subscription?.cancel();
        _client?.dispose();
      });
    }
    unawaited(_client!.connect());

    return dashboard.cgm;
  }

  void _onFrame(RealtimeFrame frame) {
    switch (frame.type) {
      case RealtimeFrameType.glucoseReading:
        final current = state.valueOrNull;
        if (current == null) return;
        final mgdlRaw = frame.data['mgdl'];
        if (mgdlRaw is! num) return;
        final mgdl = mgdlRaw.toInt();
        state = AsyncData(current.copyWith(
          currentGlucose: mgdl,
          trend: parseGlucoseTrend(frame.data['trend'] as String?),
          currentStatus: parseGlucoseStatus(mgdl),
          lastUpdatedMinutesAgo: 0,
        ));
      case RealtimeFrameType.resync:
        // The hub couldn't reconcile our resume point (e.g. it restarted) —
        // re-fetch a full snapshot over REST instead of trusting stale state.
        ref.invalidate(dashboardProvider);
      case RealtimeFrameType.hello:
      case RealtimeFrameType.glucoseState:
      case RealtimeFrameType.ping:
      case RealtimeFrameType.unknown:
        break;
    }
  }
}

final cgmProvider =
    AsyncNotifierProvider.autoDispose<CGMNotifier, CGMState>(CGMNotifier.new);

// ── Manual glucose logging ────────────────────────────────────────────────────

final manualGlucoseProvider = Provider((ref) => ManualGlucoseService(ref));

class ManualGlucoseService {
  final Ref _ref;
  ManualGlucoseService(this._ref);

  Future<void> logReading(double value, {DateTime? timestamp}) async {
    await _ref.read(apiClientProvider).post('/glucose/manual', data: {
      'value_mgdl': value.round(),
      'timestamp': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
    });
    // Invalidate dashboard so glucose card and all sections refresh
    _ref.invalidate(dashboardProvider);
  }
}
