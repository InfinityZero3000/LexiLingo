import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/network/backend_auth_header_provider.dart'
    show isAccessTokenExpiring;
import 'package:lexilingo_app/core/network/envelope.dart';
import '../constants/api_endpoints.dart';
import '../storage/admin_session_store.dart';

const _retriedFlag = '__auth_retried';

/// The admin app's HTTP client. It has its own session ([AdminSessionStore])
/// so signing in here never touches the learner's tokens.
///
/// Backend refresh tokens are single-use (rotated on every /auth/refresh), so
/// concurrent refreshes would spend the same token twice and log the admin
/// out. The first caller does the work; the rest await the same result.
///
/// Failures surface as [DioException]; `AdminApiError.from` turns one into
/// something a screen can show.
class ApiClient {
  ApiClient._(this._store, Dio? dio, Dio? refreshDio)
    : _dio = dio ?? _defaultDio(),
      _refreshDio = refreshDio ?? Dio() {
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  @visibleForTesting
  ApiClient.forTesting({
    required AdminSessionStore store,
    required Dio dio,
    required Dio refreshDio,
  }) : this._(store, dio, refreshDio);

  static ApiClient? _instance;
  static ApiClient get instance =>
      _instance ??= ApiClient._(const TokenStorageSessionStore(), null, null);

  static Dio _defaultDio() => Dio(
    BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  final AdminSessionStore _store;
  final Dio _dio;
  final Dio _refreshDio;
  Completer<bool>? _refreshCompleter;

  Dio get dio => _dio;

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    var token = await _store.accessToken();
    // Renew before the request instead of after a 401: the 401 path cannot
    // recover uploads or any request replayed outside this client.
    if (token != null && isAccessTokenExpiring(token)) {
      if (await _tryRefresh()) token = await _store.accessToken();
    }
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final options = error.requestOptions;
    if (error.response?.statusCode == 401 &&
        options.extra[_retriedFlag] != true) {
      if (await _tryRefresh()) {
        // Guard against a refresh that keeps succeeding while the request keeps
        // returning 401, which would loop forever.
        options.extra[_retriedFlag] = true;
        options.headers['Authorization'] =
            'Bearer ${await _store.accessToken()}';
        try {
          handler.resolve(await _dio.fetch(options));
          return;
        } on DioException catch (retryError) {
          handler.next(retryError);
          return;
        }
      }
      await _store.clear();
    }
    handler.next(error);
  }

  Future<bool> _tryRefresh() async {
    final pending = _refreshCompleter;
    if (pending != null) return pending.future;

    final completer = Completer<bool>();
    _refreshCompleter = completer;
    var ok = false;
    try {
      final refreshToken = await _store.refreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        final response = await _refreshDio.post(
          '${ApiEndpoints.baseUrl}${ApiEndpoints.refreshToken}',
          data: {'refresh_token': refreshToken},
        );
        final data = unwrapEnvelope(response.data);
        if (response.statusCode == 200 && data is Map) {
          await _store.saveTokens(
            accessToken: data['access_token'].toString(),
            refreshToken: (data['refresh_token'] ?? refreshToken).toString(),
          );
          ok = true;
        }
      }
    } catch (_) {
      ok = false;
    } finally {
      _refreshCompleter = null;
      completer.complete(ok);
    }
    return ok;
  }

  /// The body with its `{data}` / `{success, data}` envelope removed, whatever
  /// shape it came in (map, list, raw).
  Future<dynamic> getData(String path, {Map<String, dynamic>? params}) async {
    final response = await _dio.get(path, queryParameters: params);
    return unwrapEnvelope(response.data);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _dio.get(path, queryParameters: params);
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> post(String path, {dynamic data}) async {
    final response = await _dio.post(path, data: data);
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> put(String path, {dynamic data}) async {
    final response = await _dio.put(path, data: data);
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> patch(String path, {dynamic data}) async {
    final response = await _dio.patch(path, data: data);
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await _dio.delete(path);
    return _asMap(response.data);
  }

  Map<String, dynamic> _asMap(Object? body) {
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    return {'data': body};
  }
}
