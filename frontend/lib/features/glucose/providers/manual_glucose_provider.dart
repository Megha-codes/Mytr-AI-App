import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/auth/auth_session_provider.dart';

// ── Simple state ──────────────────────────────────────────────────────────────

class ManualGlucoseState {
  final bool    isSaving;
  final String? error;

  const ManualGlucoseState({this.isSaving = false, this.error});
}

// ── Ephemeral input providers (reset when the sheet closes) ───────────────────

class GlucoseInputNotifier extends Notifier<int> {
  @override
  int build() => 100;
  void update(int value) => state = value;
}

/// The glucose value the user is currently entering (mg/dL)
final glucoseInputProvider = NotifierProvider<GlucoseInputNotifier, int>(() => GlucoseInputNotifier());

class ReadingTimeNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();
  void update(DateTime time) => state = time;
}

/// Timestamp for the reading — defaults to now; user can backfill
final readingTimeProvider = NotifierProvider<ReadingTimeNotifier, DateTime>(() => ReadingTimeNotifier());

// ── Save notifier ─────────────────────────────────────────────────────────────

class ManualGlucoseNotifier extends Notifier<ManualGlucoseState> {
  late Dio _dio;

  @override
  ManualGlucoseState build() {
    _dio = ref.watch(dioProvider);
    return const ManualGlucoseState();
  }

  Future<void> save({required int valueMgdl, required DateTime timestamp}) async {
    final userId = ref.read(authSessionProvider);
    state = const ManualGlucoseState(isSaving: true);
    try {
      await _dio.post(
        '/api/v1/glucose/manual',
        data: {
          'user_id':    userId,
          'value_mgdl': valueMgdl,
          'timestamp':  timestamp.toIso8601String(),
        },
      );
      state = const ManualGlucoseState();
    } on DioException catch (e) {
      state = ManualGlucoseState(
        error: e.response?.data?['detail']?.toString() ??
            'Failed to save reading. Please try again.',
      );
    }
  }
}

final manualGlucoseProvider =
    NotifierProvider<ManualGlucoseNotifier, ManualGlucoseState>(() {
  return ManualGlucoseNotifier();
});
