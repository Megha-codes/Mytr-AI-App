/// A hand-rolled fake of [ApiClient] for tests — no mocking package needed
/// (Dart gives every class an implicit interface, so `implements ApiClient`
/// is enough). Stubs exactly the endpoints exercised by the providers under
/// test; anything else throws [UnimplementedError] so an unstubbed call
/// fails loudly in the test instead of returning a confusing null.
///
/// [respondingAs] simulates "which account is currently authenticated" —
/// toggle it between requests the same way a real backend's responses would
/// differ once a different user's token is on the request. It only affects
/// responses that are meant to reflect account-scoped data (currently just
/// GET /devices, tagged into the device id so a test can tell a real
/// re-fetch happened from a stale cached one); the point of most of this
/// fake is that its answers *don't* vary by account, and the regression
/// this supports is entirely about whether the CLIENT throws stale
/// responses away on logout, not about what the fake server sends.
library;

import 'package:dio/dio.dart';
import 'package:metasync_app/core/api/api_client.dart';

class FakeApiClient implements ApiClient {
  String respondingAs = 'a';

  /// Incremented on every GET /devices — lets a test prove a provider
  /// genuinely re-fetched after invalidation rather than serving a cached
  /// value (Riverpod wouldn't call build() again, so this wouldn't move).
  int devicesFetchCount = 0;

  Response<T> _ok<T>(String path, dynamic data) {
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: data as T,
    );
  }

  @override
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) async {
    if (path == '/devices') {
      devicesFetchCount++;
      return _ok(path, [
        {'device_id': 'device-$respondingAs', 'kind': 'DESK', 'name': 'Device of $respondingAs'},
      ]);
    }
    throw UnimplementedError('FakeApiClient: unstubbed GET $path');
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    switch (path) {
      case '/auth/login':
        final email = (data as Map)['email'] as String;
        return _ok(path, {'access_token': 'access-$email', 'refresh_token': 'refresh-$email'});
      case '/auth/logout-all':
        return _ok(path, <String, dynamic>{});
      case '/chat':
        return _ok(path, {
          'reply': 'reply for $respondingAs',
          'conversation_id': 'conv-$respondingAs',
          'tools_used': <String>[],
        });
      case '/inference/bolus':
        return _ok(path, {
          'recommended_dose': 5.0,
          'base_bolus': 4.0,
          'lifestyle_adjustment_percent': 10.0,
          'drivers': ['carbs'],
          'confidence': 0.9,
          'show_doctor_flag': false,
          'is_personalised': true,
        });
      default:
        throw UnimplementedError('FakeApiClient: unstubbed POST $path');
    }
  }

  @override
  Future<Response<T>> put<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    throw UnimplementedError('FakeApiClient: unstubbed PUT $path');
  }

  @override
  Future<Response<T>> patch<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    throw UnimplementedError('FakeApiClient: unstubbed PATCH $path');
  }

  @override
  Future<Response<T>> delete<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    throw UnimplementedError('FakeApiClient: unstubbed DELETE $path');
  }
}
