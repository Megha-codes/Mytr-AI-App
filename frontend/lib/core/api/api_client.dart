import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_storage_service.dart';
import '../config.dart';

final apiClientProvider = Provider((ref) {
  return ApiClient();
});

class ApiClient {
  final AuthStorageService _storage = AuthStorageService();
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final token = await _storage.getAccessToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          } catch (_) {
            // Corrupted secure storage — proceed without token
          }
          return handler.next(options);
        },
      ),
    );

    // ── Refresh Interceptor (401 Handling) ──────────────────────────────────
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onError: (DioException e, handler) async {
          // Only attempt a refresh-and-retry for 401s on protected endpoints.
          // The auth endpoints themselves must be excluded:
          //   • /auth/login   — a 401 means wrong credentials, not an expired token.
          //   • /auth/refresh — refreshing on a failed refresh would loop forever.
          // Anything under /auth/ (forgot/reset password etc.) is also excluded.
          final path = e.requestOptions.path;
          final isAuthEndpoint = path.contains('/auth/');

          if (e.response?.statusCode == 401 && !isAuthEndpoint) {
            final success = await _refreshToken();
            if (success) {
              // Retry the original request with the new access token.
              final token = await _storage.getAccessToken();
              e.requestOptions.headers['Authorization'] = 'Bearer $token';
              final cloneReq = await _dio.request(
                e.requestOptions.path,
                options: Options(
                  method: e.requestOptions.method,
                  headers: e.requestOptions.headers,
                ),
                data: e.requestOptions.data,
                queryParameters: e.requestOptions.queryParameters,
              );
              return handler.resolve(cloneReq);
            }
            // Refresh failed — the session is dead. Clear tokens so the app
            // falls back to the unauthenticated state and redirects to login.
            await _storage.clearAll();
            return handler.next(e);
          }
          return handler.next(e);
        },
      ),
    );

    // ── Retry Interceptor ──────────────────────────────────────────────────
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        logPrint: kDebugMode ? print : null,
        retries: 3,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ],
      ),
    );

    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestHeader: true,
          requestBody: true,
          responseHeader: false,
          responseBody: true,
          error: true,
        ),
      );
    }
  }

  Future<bool> _refreshToken() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      if (response.statusCode == 200) {
        await _storage.saveTokens(
          access: response.data['access_token'],
          refresh: response.data['refresh_token'],
        );
        return true;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  // ── Convenience Methods ─────────────────────────────────────────────────
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.post<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> put<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return _dio.put<T>(path, data: data, queryParameters: queryParameters);
  }

  Future<Response<T>> delete<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return _dio.delete<T>(path, data: data, queryParameters: queryParameters);
  }
}
