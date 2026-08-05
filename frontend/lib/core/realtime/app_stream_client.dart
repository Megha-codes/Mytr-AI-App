import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

/// Frame types the server sends over the versioned envelope
/// (architecture-v3.md §2.6): `{v, type, ts, seq, data}`. `resync` is the
/// one exception — a bare, un-versioned `{"type":"resync"}` control frame
/// sent in reply to a resume request the server can't reconcile.
enum RealtimeFrameType { hello, glucoseReading, glucoseState, ping, resync, unknown }

class RealtimeFrame {
  final RealtimeFrameType type;
  final int? seq;
  final Map<String, dynamic> data;

  const RealtimeFrame({required this.type, this.seq, required this.data});
}

RealtimeFrameType _frameTypeFor(String? type) => switch (type) {
      'hello' => RealtimeFrameType.hello,
      'glucose.reading' => RealtimeFrameType.glucoseReading,
      'glucose.state' => RealtimeFrameType.glucoseState,
      'ping' => RealtimeFrameType.ping,
      'resync' => RealtimeFrameType.resync,
      _ => RealtimeFrameType.unknown,
    };

/// Client for /ws/app/stream (architecture-v3.md §2.6). Auth travels in the
/// Sec-WebSocket-Protocol header as `bearer, <token>` — `protocols: ['bearer',
/// token]` on `WebSocketChannel.connect` is what produces that header on
/// every platform (native and web both derive Sec-WebSocket-Protocol from
/// the WebSocket handshake's subprotocol list, so no manual header plumbing
/// is needed or even possible here).
///
/// Handles the reconnect/resume contract itself: on every successful
/// connection (including the first) it sends `{"type":"resume",
/// "since_seq":N}` right after `hello`, using whatever seq it last saw — so a
/// dropped connection resumes from where it left off instead of silently
/// losing readings. A `resync` reply (or any handshake/connect failure)
/// triggers a reconnect with capped backoff; callers should treat a `resync`
/// frame as "re-fetch a snapshot over REST," which is exactly what
/// [RealtimeFrameType.resync] is for.
class AppStreamClient {
  AppStreamClient({required Future<String?> Function() getAccessToken})
      : _getAccessToken = getAccessToken;

  final Future<String?> Function() _getAccessToken;

  final _controller = StreamController<RealtimeFrame>.broadcast();
  Stream<RealtimeFrame> get frames => _controller.stream;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _lastSeq = 0;
  int _reconnectAttempt = 0;
  bool _stopped = false;
  bool _connecting = false;
  bool _connected = false;

  static const _path = '/ws/app/stream';
  static const _maxBackoff = Duration(seconds: 30);

  /// Safe to call repeatedly (e.g. from a Riverpod `build()` that reruns
  /// whenever a watched provider changes) — a no-op while already connected
  /// or mid-handshake, so it never leaks a duplicate socket.
  Future<void> connect() async {
    if (_stopped || _connecting || _connected) return;
    _connecting = true;
    _reconnectTimer?.cancel();

    final token = await _getAccessToken();
    if (token == null) {
      // Not logged in (yet) — retry later rather than failing hard; auth
      // state can arrive shortly after this client is created.
      _connecting = false;
      _scheduleReconnect();
      return;
    }
    if (_stopped) {
      _connecting = false;
      return;
    }

    try {
      final uri = Uri.parse('${AppConfig.wsBaseUrl}$_path');
      _channel = WebSocketChannel.connect(uri, protocols: ['bearer', token]);
      await _channel!.ready;
      _connected = true;
      _connecting = false;
      _reconnectAttempt = 0;
      _subscription = _channel!.stream.listen(
        _onData,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _connecting = false;
      _channel = null;
      _handleDisconnect();
    }
  }

  void _onData(dynamic raw) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = _frameTypeFor(json['type'] as String?);
    final seq = json['seq'] as int?;
    if (seq != null) _lastSeq = seq;

    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    _controller.add(RealtimeFrame(type: type, seq: seq, data: data));

    if (type == RealtimeFrameType.hello) {
      _sendResume();
    } else if (type == RealtimeFrameType.resync) {
      // The hub can't reconcile our since_seq (e.g. it restarted) — nothing
      // more to replay on this connection; the consumer re-syncs via REST.
    }
  }

  void _sendResume() {
    _channel?.sink.add(jsonEncode({'type': 'resume', 'since_seq': _lastSeq}));
  }

  void _handleDisconnect() {
    _connected = false;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_stopped) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delaySeconds = (1 << _reconnectAttempt).clamp(1, _maxBackoff.inSeconds);
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), connect);
  }

  void disconnect() {
    _stopped = true;
    _connected = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
