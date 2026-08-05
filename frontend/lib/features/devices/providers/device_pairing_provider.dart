import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../models/paired_device.dart';

// ── Result type (mirrors ConnectionResult in cgm_connect_provider.dart) ───────

class PairResult {
  final bool success;
  final PairedDevice? device;
  final String? errorMessage;

  const PairResult({required this.success, this.device, this.errorMessage});
}

// ── State ─────────────────────────────────────────────────────────────────────

class DevicePairingState {
  final bool isLoading;
  final String? error;

  const DevicePairingState({this.isLoading = false, this.error});

  DevicePairingState copyWith({bool? isLoading, String? error}) {
    return DevicePairingState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class DevicePairingNotifier extends Notifier<DevicePairingState> {
  @override
  DevicePairingState build() => const DevicePairingState();

  /// Claims a pairing code shown on the desk device (POST /devices/pair).
  /// Uses the real, JWT-authenticated ApiClient — the backend requires a
  /// Bearer token, not a user_id in the body.
  Future<PairResult> claim({required String code, String? name}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final trimmedName = name?.trim();
      final response = await ref.read(apiClientProvider).post('/devices/pair', data: {
        'code': code,
        if (trimmedName != null && trimmedName.isNotEmpty) 'name': trimmedName,
      });
      state = state.copyWith(isLoading: false);
      final data = response.data as Map<String, dynamic>;
      return PairResult(
        success: true,
        device: PairedDevice(
          deviceId: data['device_id'] as String,
          name: data['name'] as String?,
          kind: 'DESK',
          pairedAt: data['paired_at'] != null ? DateTime.parse(data['paired_at'] as String) : null,
        ),
      );
    } on DioException catch (e) {
      final message = e.response?.data?['detail']?.toString() ??
          'Failed to pair device. Check the code and try again.';
      state = state.copyWith(isLoading: false, error: message);
      return PairResult(success: false, errorMessage: message);
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final devicePairingProvider =
    NotifierProvider<DevicePairingNotifier, DevicePairingState>(() {
  return DevicePairingNotifier();
});
