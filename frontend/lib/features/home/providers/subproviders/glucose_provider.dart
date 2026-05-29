import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../models/models.dart';
import 'dashboard_provider.dart';

// ── CGM provider — derived from dashboardProvider ─────────────────────────────

class CGMNotifier extends AutoDisposeAsyncNotifier<CGMState> {
  @override
  FutureOr<CGMState> build() async {
    final dashboard = await ref.watch(dashboardProvider.future);
    return dashboard.cgm;
  }
}

final cgmProvider =
    AsyncNotifierProvider.autoDispose<CGMNotifier, CGMState>(CGMNotifier.new);

// ── Manual glucose logging ────────────────────────────────────────────────────

final manualGlucoseProvider = Provider((ref) => ManualGlucoseService(ref));

class ManualGlucoseService {
  final Ref _ref;
  ManualGlucoseService(this._ref);

  Future<void> logReading(double value) async {
    await _ref.read(apiClientProvider).post('/glucose/manual', data: {
      'value_mgdl': value.round(),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    // Invalidate dashboard so glucose card and all sections refresh
    _ref.invalidate(dashboardProvider);
  }
}
