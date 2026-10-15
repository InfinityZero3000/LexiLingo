import 'dart:async';

import 'package:dio/dio.dart';
import '../../../../core/network/backend_auth_header_provider.dart'
    show isAccessTokenExpiring;
import '../constants/api_endpoints.dart';
import '../storage/token_storage.dart';

/// Backend refresh tokens are single-use (rotated on every /auth/refresh), so
/// concurrent refreshes would spend the same token twice and log the admin out.
/// The first caller does the work; the rest await the same result.
Completer<bool>? _refreshCompleter;

const _retriedFlag = '__auth_retried';

class ApiClient {
  static ApiClient? _instance;
  late final Dio _dio;

  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        var token = await TokenStorage.getAccessToken();
        // Renew before the request instead of after a 401 — the 401 path cannot
        // recover uploads or any request replayed outside this client.
        if (token != null && isAccessTokenExpiring(token)) {
          if (await _tryRefresh()) {
            token = await TokenStorage.getAccessToken();
          }
        }
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final options = error.requestOptions;
        if (error.response?.statusCode == 401 &&
            options.extra[_retriedFlag] != true) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            // Guard against a refresh that keeps succeeding while the request
            // keeps returning 401 — otherwise fetch() loops forever.
            options.extra[_retriedFlag] = true;
            final token = await TokenStorage.getAccessToken();
            options.headers['Authorization'] = 'Bearer $token';
            try {
              handler.resolve(await _dio.fetch(options));
              return;
            } on DioException catch (retryError) {
              handler.next(retryError);
              return;
            }
          }
          await TokenStorage.clear();
        }
        handler.next(error);
      },
    ));
  }

  static ApiClient get instance => _instance ??= ApiClient._();

  Dio get dio => _dio;

  Future<bool> _tryRefresh() async {
    final pending = _refreshCompleter;
    if (pending != null) return pending.future;

    final completer = Completer<bool>();
    _refreshCompleter = completer;
    try {
      final refreshToken = await TokenStorage.getRefreshToken();
      if (refreshToken == null) {
        completer.complete(false);
        return false;
      }

      final response = await Dio().post(
        '${ApiEndpoints.baseUrl}${ApiEndpoints.refreshToken}',
        data: {'refresh_token': refreshToken},
      );
      if (response.statusCode == 200) {
        final data = response.data['data'];
        await TokenStorage.saveTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'] ?? refreshToken,
        );
        completer.complete(true);
        return true;
      }
    } catch (_) {
      // Fall through to the failure result below.
    } finally {
      _refreshCompleter = null;
    }
    if (!completer.isCompleted) completer.complete(false);
    return false;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    final response = await _dio.get(path, queryParameters: params);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(String path, {dynamic data}) async {
    final response = await _dio.post(path, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> put(String path, {dynamic data}) async {
    final response = await _dio.put(path, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(String path, {dynamic data}) async {
    final response = await _dio.patch(path, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await _dio.delete(path);
    return response.data as Map<String, dynamic>;
  }
}
