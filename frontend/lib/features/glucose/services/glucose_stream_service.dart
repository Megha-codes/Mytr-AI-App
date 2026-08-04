import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/glucose_reading.dart';
import '../../../core/config.dart';

class GlucoseStreamService {
  final String baseWsUrl;
  WebSocketChannel? _channel;

  /// [baseWsUrl] defaults to the value derived from [AppConfig.wsBaseUrl]
  /// so there is no hardcoded URL in this file.
  GlucoseStreamService({String? baseWsUrl})
      : baseWsUrl = baseWsUrl ?? AppConfig.wsBaseUrl;

  Stream<GlucoseReading> connect(String accessToken) {
    _channel = WebSocketChannel.connect(
      Uri.parse('$baseWsUrl/ws/glucose').replace(
        queryParameters: {'token': accessToken},
      ),
    );

    return _channel!.stream
        .map((data) => jsonDecode(data as String) as Map<String, dynamic>)
        .where((json) =>
            json['type'] == 'GLUCOSE_READING' ||
            json['type'] == 'MANUAL_READING')
        .map(GlucoseReading.fromJson);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}

final glucoseStreamServiceProvider = Provider<GlucoseStreamService>((ref) {
  return GlucoseStreamService();
});

// StreamProvider.family — pass the caller's access token at the call site
final glucoseStreamProvider =
    StreamProvider.autoDispose.family<GlucoseReading, String>((ref, accessToken) {
  final service = ref.watch(glucoseStreamServiceProvider);
  ref.onDispose(service.disconnect);
  return service.connect(accessToken);
});
