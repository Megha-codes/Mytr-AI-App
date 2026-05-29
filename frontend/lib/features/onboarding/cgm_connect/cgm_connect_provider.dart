import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/auth/auth_session_provider.dart';

// ── Shared result type (used by connectLibre; Dexcom returns bool) ────────────

class ConnectionResult {
  final bool    success;
  final String? errorMessage;

  const ConnectionResult({required this.success, this.errorMessage});

  static const ok = ConnectionResult(success: true);
}

// ── State ─────────────────────────────────────────────────────────────────────

class CgmConnectState {
  final bool    isLoading;
  final String? error;

  const CgmConnectState({this.isLoading = false, this.error});

  CgmConnectState copyWith({bool? isLoading, String? error}) {
    return CgmConnectState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class CgmConnectNotifier extends Notifier<CgmConnectState> {
  late Dio _dio;

  @override
  CgmConnectState build() {
    _dio = ref.watch(dioProvider);
    return const CgmConnectState();
  }

  // Dexcom ─────────────────────────────────────────────────────────────────

  Future<bool> exchangeDexcomCode(String code) async {
    final userId = ref.read(authSessionProvider);
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _dio.post(
        '/api/v1/cgm/connect/dexcom',
        data: {'code': code, 'user_id': userId},
      );
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.response?.data?['detail']?.toString() ??
            'Failed to connect Dexcom. Please try again.',
      );
      return false;
    }
  }

  // Libre ──────────────────────────────────────────────────────────────────

  Future<ConnectionResult> connectLibre({
    required String email,
    required String password,
  }) async {
    final userId = ref.read(authSessionProvider);
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _dio.post(
        '/api/v1/cgm/connect/libre',
        data: {'email': email, 'password': password, 'user_id': userId},
      );
      state = state.copyWith(isLoading: false);
      return ConnectionResult.ok;
    } on DioException catch (e) {
      final message = e.response?.data?['detail']?.toString() ??
          'Failed to connect Libre. Check your credentials and try again.';
      state = state.copyWith(isLoading: false, error: message);
      return ConnectionResult(success: false, errorMessage: message);
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final cgmConnectProvider =
    NotifierProvider<CgmConnectNotifier, CgmConnectState>(() {
  return CgmConnectNotifier();
});
