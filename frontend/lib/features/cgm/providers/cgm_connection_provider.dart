import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/config.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session_provider.dart';
import '../models/cgm_device_type.dart';
import '../models/cgm_connection_state.dart';
import '../models/cgm_connected_info.dart';

class CgmConnectionNotifier extends Notifier<CgmConnectionState> {
  late ApiClient _api;
  WebSocketChannel? _wsChannel;

  @override
  CgmConnectionState build() {
    // Was ref.watch(dioProvider) — a bare Dio with no auth interceptor at
    // all (see core/network/dio_provider.dart), so every call below sent no
    // Authorization header whatsoever. It went unnoticed because these
    // calls also still passed a stale `user_id` query param/body field left
    // over from an earlier, pre-auth version of these routes — cgm_connect.py
    // now takes the user from Depends(get_current_user) exclusively, so
    // every call here was 401ing for the real reason (no token) while
    // looking, from the call site, like it should have been identifying the
    // user correctly. apiClientProvider is the client that actually attaches
    // the bearer token (and retries once on a 401 after a token refresh).
    _api = ref.watch(apiClientProvider);
    _initWebSocket();
    return const CgmConnectionState();
  }

  void _initWebSocket() {
    final userId = ref.read(authSessionProvider);
    if (userId == null) return;

    final wsUrl = '${AppConfig.wsBaseUrl}/ws/sensor-status/$userId';
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel!.stream.listen((message) {
        final data = jsonDecode(message);
        if (data['type'] == 'SENSOR_STATUS') {
          state = state.copyWith(sensorStatus: data['status']);
        }
      }, onError: (_) {
        // Reconnect after delay
        Future.delayed(const Duration(seconds: 10), _initWebSocket);
      });
    } catch (_) {}
  }

  // ── Libre credential flow ──────────────────────────────────────────────────

  Future<void> connectLibre(String email, String password) async {
    state = const CgmConnectionState(status: CgmConnectionStatus.validating);

    try {
      // user_id used to be sent as a query param here — the route now
      // identifies the caller purely from the bearer token (see the
      // comment on _api above), so it's dropped rather than kept as dead
      // weight that misleads readers into thinking the backend uses it.
      final response = await _api.post(
        '/cgm/connect/libre',
        data: {'email': email, 'password': password},
      );

      final data = response.data as Map<String, dynamic>;
      if (data['connected'] != true) {
        state = CgmConnectionState(
          status: CgmConnectionStatus.connectionFailed,
          error: _mapLibreBackendError(data['error_code'] as String?),
        );
        return;
      }

      final info = CgmConnectedInfo.fromJson(response.data as Map<String, dynamic>);
      state = CgmConnectionState(
        status: CgmConnectionStatus.connected,
        connectedDevice: CgmDeviceType.libreThree,
        connectedInfo: info,
        sensorStatus: info.sensorStatus,
      );
    } on DioException catch (e) {
      state = CgmConnectionState(status: CgmConnectionStatus.connectionFailed, error: _mapDioError(e));
    }
  }

  // ── Manual entry ───────────────────────────────────────────────────────────

  Future<void> setManualEntry() async {
    state = const CgmConnectionState(status: CgmConnectionStatus.validating);

    try {
      final response = await _api.post('/cgm/connect/manual');

      final info = CgmConnectedInfo.fromJson(response.data as Map<String, dynamic>);
      state = CgmConnectionState(
        status: CgmConnectionStatus.connected,
        connectedDevice: CgmDeviceType.manual,
        connectedInfo: info,
      );
    } on DioException catch (e) {
      state = CgmConnectionState(status: CgmConnectionStatus.connectionFailed, error: _mapDioError(e));
    }
  }

  Future<void> disconnect() async {
    try {
      // The route is DELETE /cgm/devices/{device_id} — there's no bare
      // "disconnect whatever is connected" endpoint, and this notifier
      // doesn't carry a device id in its state (CgmConnectedInfo never
      // gained one). Fetching the list first and deleting the active entry
      // is the only way to disconnect with what the backend actually
      // exposes, and matches there being exactly one CGM per user in
      // practice today (this fixes the previous call, which also used to
      // hit a route — DELETE /cgm/devices with a bare user_id query param
      // — that never matched the real path shape at all, on top of the
      // missing-auth bug every other call in this file had).
      final devices = (await _api.get('/cgm/devices')).data as List<dynamic>;
      final active = devices.cast<Map<String, dynamic>>().firstWhere(
            (d) => d['is_active'] == true,
            orElse: () => devices.isNotEmpty ? devices.first as Map<String, dynamic> : {},
          );
      final deviceId = active['id'] as String?;
      if (deviceId != null) {
        await _api.delete('/cgm/devices/$deviceId');
      }
      state = const CgmConnectionState();
    } catch (_) {
      // Still reset locally even if backend fails
      state = const CgmConnectionState();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void reset() => state = const CgmConnectionState();

  CgmConnectError _mapDioError(DioException e) {
    if (e.response?.statusCode == 429) {
      return CgmConnectError.timeout; // We'll map rate limit to timeout for now as per simple error enum
    }
    return CgmConnectError.backendUnavailable;
  }

  CgmConnectError _mapLibreBackendError(String? code) {
    return switch (code) {
      'INVALID_CREDENTIALS' => CgmConnectError.libreInvalidCredentials,
      'CONNECTIONS_NOT_ENABLED' => CgmConnectError.libreSetupNotDone,
      'NO_ACTIVE_SENSOR' => CgmConnectError.libreNoActiveSensor,
      'SERVICE_UNAVAILABLE' => CgmConnectError.libreServerUnavailable,
      _ => CgmConnectError.backendUnavailable,
    };
  }
}

final cgmConnectionProvider = NotifierProvider<CgmConnectionNotifier, CgmConnectionState>(() {
  return CgmConnectionNotifier();
});
