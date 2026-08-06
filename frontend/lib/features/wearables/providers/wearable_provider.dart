import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/google_health_service.dart';
import '../services/health_sync_service.dart';
import '../../../core/services/health_service.dart';

class WearableConnectionState {
  final bool healthConnected;       // HealthKit (iOS) / Health Connect (Android)
  final bool googleHealthConnected; // Fitbit via Google Health API
  final DateTime? healthLastSync;
  final DateTime? googleHealthLastSync;

  const WearableConnectionState({
    this.healthConnected = false,
    this.googleHealthConnected = false,
    this.healthLastSync,
    this.googleHealthLastSync,
  });

  String get healthName {
    if (kIsWeb) return 'Apple Health / Health Connect';
    return defaultTargetPlatform == TargetPlatform.iOS
        ? 'Apple Health'
        : 'Health Connect';
  }

  WearableConnectionState copyWith({
    bool? healthConnected,
    bool? googleHealthConnected,
    DateTime? healthLastSync,
    DateTime? googleHealthLastSync,
  }) =>
      WearableConnectionState(
        healthConnected: healthConnected ?? this.healthConnected,
        googleHealthConnected:
            googleHealthConnected ?? this.googleHealthConnected,
        healthLastSync: healthLastSync ?? this.healthLastSync,
        googleHealthLastSync: googleHealthLastSync ?? this.googleHealthLastSync,
      );
}

class WearableNotifier extends AsyncNotifier<WearableConnectionState> {
  HealthService get _health => HealthService.instance;
  GoogleHealthService get _googleHealth => GoogleHealthService.instance;

  @override
  FutureOr<WearableConnectionState> build() async {
    await _health.configure();
    final results = await Future.wait([
      _health.isAuthorized(),
      _googleHealth.isConnected(),
    ]);
    return WearableConnectionState(
      healthConnected: results[0],
      googleHealthConnected: results[1],
    );
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

  Future<void> connectGoogleHealth() async {
    await _googleHealth.connect();
    state = AsyncData(
      (state.valueOrNull ?? const WearableConnectionState()).copyWith(
        googleHealthConnected: true,
        googleHealthLastSync: DateTime.now(),
      ),
    );
    unawaited(ref.read(healthSyncServiceProvider).sync());
  }

  Future<void> disconnectGoogleHealth() async {
    await _googleHealth.disconnect();
    state = AsyncData(
      (state.valueOrNull ?? const WearableConnectionState())
          .copyWith(googleHealthConnected: false),
    );
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
