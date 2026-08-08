import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/health_sync_service.dart';
import '../../../core/services/health_service.dart';

/// Fitbit is no longer a separate connect path. It used to be a direct
/// OAuth login against Google's Health API (see git history —
/// GoogleHealthService, removed) — but on Android, Fitbit's own app writes
/// into Health Connect directly, and Health Connect is OS-level (built in
/// on Android 14+, a permission grant rather than a separate account
/// login). So "connect Health Connect" already covers Fitbit for anyone
/// whose Fitbit app is set to sync there — no second login screen needed.
class WearableConnectionState {
  final bool healthConnected; // HealthKit (iOS) / Health Connect (Android) — Fitbit included on Android
  final DateTime? healthLastSync;

  const WearableConnectionState({
    this.healthConnected = false,
    this.healthLastSync,
  });

  String get healthName {
    if (kIsWeb) return 'Apple Health / Health Connect';
    return defaultTargetPlatform == TargetPlatform.iOS
        ? 'Apple Health'
        : 'Google Health Connect / Fitbit';
  }

  WearableConnectionState copyWith({
    bool? healthConnected,
    DateTime? healthLastSync,
  }) =>
      WearableConnectionState(
        healthConnected: healthConnected ?? this.healthConnected,
        healthLastSync: healthLastSync ?? this.healthLastSync,
      );
}

class WearableNotifier extends AsyncNotifier<WearableConnectionState> {
  HealthService get _health => HealthService.instance;

  @override
  FutureOr<WearableConnectionState> build() async {
    await _health.configure();
    final authorized = await _health.isAuthorized();
    return WearableConnectionState(healthConnected: authorized);
  }

  Future<void> connectHealth() async {
    final granted = await _health.requestPermissions();
    if (!granted) throw Exception('Health permissions were denied');
    state = AsyncData(
      (state.valueOrNull ?? const WearableConnectionState()).copyWith(
        healthConnected: true,
        healthLastSync: DateTime.now(),
      ),
    );
    // Fire the first sync immediately — otherwise "connected" would sit
    // there with no data until the next foreground/pull-to-refresh.
    unawaited(ref.read(healthSyncServiceProvider).sync());
  }

  void disconnectHealth() {
    state = AsyncData(
      (state.valueOrNull ?? const WearableConnectionState())
          .copyWith(healthConnected: false),
    );
  }
}

final wearableProvider =
    AsyncNotifierProvider<WearableNotifier, WearableConnectionState>(
  WearableNotifier.new,
);
