import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/auth/auth_session_provider.dart';
import '../models/cgm_device_type.dart';
import '../models/cgm_connection_state.dart';
import '../models/cgm_connected_info.dart';

class CgmConnectionNotifier extends Notifier<CgmConnectionState> {
  late Dio _dio;
  WebSocketChannel? _wsChannel;

  @override
  CgmConnectionState build() {
    _dio = ref.watch(dioProvider);
    _initWebSocket();
    return const CgmConnectionState();
  }

  void _initWebSocket() {
    final userId = ref.read(authSessionProvider);
    if (userId == null) return;

    final wsUrl = 'ws://localhost:8000/ws/sensor-status/$userId';
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

  // ── Dexcom OAuth flow ───────────────────────────────────────────────────────

  Future<void> connectDexcom() async {
    state = const CgmConnectionState(status: CgmConnectionStatus.connecting);

    try {
      final userId = ref.read(authSessionProvider);
      final response = await _dio.get('/cgm/oauth/dexcom/url', queryParameters: {'user_id': userId});
      final authUrl = response.data['url'] as String;
      
      // Extract state from URL
      final uri = Uri.parse(authUrl);
      final stateNonce = uri.queryParameters['state'] ?? '';

      final callbackResult = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: 'mytrai',
      );

      final code = Uri.parse(callbackResult).queryParameters['code'];
      if (code == null) throw Exception('No code returned');

      state = const CgmConnectionState(status: CgmConnectionStatus.validating);
      await _exchangeDexcomCode(code: code, stateNonce: stateNonce);
    } catch (e) {
      state = CgmConnectionState(
        status: CgmConnectionStatus.connectionFailed, 
        error: e is DioException ? _mapDioError(e) : CgmConnectError.dexcomAuthCancelled
      );
    }
  }

  Future<void> _exchangeDexcomCode({required String code, required String stateNonce}) async {
    try {
      final userId = ref.read(authSessionProvider);
      final response = await _dio.post(
        '/cgm/connect/dexcom',
        queryParameters: {'user_id': userId},
        data: {'code': code, 'state': stateNonce},
      );

      final info = CgmConnectedInfo.fromJson(response.data as Map<String, dynamic>);
      state = CgmConnectionState(
        status: CgmConnectionStatus.connected,
        connectedDevice: CgmDeviceType.dexcomG7,
        connectedInfo: info,
        sensorStatus: info.sensorStatus,
      );
    } on DioException catch (e) {
      state = CgmConnectionState(status: CgmConnectionStatus.connectionFailed, error: _mapDioError(e));
    }
  }

  // ── Libre credential flow ──────────────────────────────────────────────────

  Future<void> connectLibre(String email, String password) async {
    state = const CgmConnectionState(status: CgmConnectionStatus.validating);

    try {
      final userId = ref.read(authSessionProvider);
      final response = await _dio.post(
        '/cgm/connect/libre',
        queryParameters: {'user_id': userId},
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
      final userId = ref.read(authSessionProvider);
      final response = await _dio.post(
        '/cgm/connect/manual',
        queryParameters: {'user_id': userId},
      );

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
      final userId = ref.read(authSessionProvider);
      await _dio.delete('/cgm/devices', queryParameters: {'user_id': userId});
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
