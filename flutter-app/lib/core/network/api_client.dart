import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../error/exceptions.dart';
import 'api_config.dart';
import 'interceptors/api_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'models.dart';
import 'network_info.dart';
import 'response_models.dart';

/// HTTP client with basic interceptors, connectivity check, and error mapping.
class ApiClient {
  final http.Client _client;
  final String _baseUrl;
  final List<ApiInterceptor> _interceptors;
  final NetworkInfo _networkInfo;
  final Future<Map<String, String>> Function()? _authHeaderProvider;
  final Future<bool> Function()? _onUnauthorized;

  ApiClient({
    http.Client? client,
    String? baseUrl,
    List<ApiInterceptor>? interceptors,
    NetworkInfo? networkInfo,
    bool enableLogging = true,
    Future<Map<String, String>> Function()? authHeaderProvider,
    Future<bool> Function()? onUnauthorized,
  }) : _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceAll(RegExp(r'/+$'), ''),
       _interceptors = [
         if (enableLogging) LoggingInterceptor(),
         ...?interceptors,
       ],
       _networkInfo = networkInfo ?? NetworkInfoImpl(),
       _authHeaderProvider = authHeaderProvider,
       _onUnauthorized = onUnauthorized;

  Future<Map<String, String>> _buildHeaders(
    Map<String, String>? headers,
  ) async {
    final built = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (_authHeaderProvider != null) {
      try {
        built.addAll(await _authHeaderProvider.call());
      } catch (_) {
        // If token fetch fails, continue without auth header.
      }
    }

    if (headers != null) {
      built.addAll(headers);
    }

    return built;
  }

  Uri _resolve(String path) {
    if (path.startsWith('http')) return Uri.parse(path);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalizedPath');
  }

  /// GET request returning unwrapped data
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final uri = _resolve(path);
    return _send('GET', uri, headers: headers, timeout: timeout);
  }

  /// POST request returning unwrapped data
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final uri = _resolve(path);
    return _send('POST', uri, headers: headers, body: body, timeout: timeout);
  }

  /// PATCH request returning unwrapped data
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final uri = _resolve(path);
    return _send('PATCH', uri, headers: headers, body: body, timeout: timeout);
  }

  /// POST multipart request returning unwrapped data.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? fields,
    required String fileField,
    required Uint8List fileBytes,
    required String filename,
    Duration? timeout,
  }) async {
    if (!await _networkInfo.isConnected) {
      throw ServerException('No network connection');
    }

    final uri = _resolve(path);

    Future<Map<String, dynamic>> sendOnce() async {
      final resolvedHeaders = await _buildHeaders(headers);
      resolvedHeaders.removeWhere(
        (key, _) => key.toLowerCase() == 'content-type',
      );

      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(resolvedHeaders);
      request.fields.addAll(fields ?? <String, String>{});
      request.files.add(
        http.MultipartFile.fromBytes(fileField, fileBytes, filename: filename),
      );

      final streamed = await request.send().timeout(
        timeout ?? ApiConfig.receiveTimeout,
      );
      final response = await http.Response.fromStream(streamed);
      final apiResponse = ApiResponse(
        statusCode: response.statusCode,
        uri: uri,
        body: response.body,
      );

      await _notifyResponse(apiResponse);
      return await _handleResponse(apiResponse);
    }

    try {
      return await sendOnce();
    } on TokenRefreshedException {
      return await sendOnce();
    } catch (e) {
      await _notifyError(
        ApiError(method: 'POST', uri: uri, cause: e, message: e.toString()),
      );
      if (e is ServerException) rethrow;
      throw ServerException('POST multipart ${uri.path} failed: $e');
    }
  }

  /// GET request returning full ApiResponseEnvelope
  Future<ApiResponseEnvelope<T>> getEnvelope<T>(
    String path, {
    Map<String, String>? headers,
    required T Function(dynamic) fromJson,
  }) async {
    final uri = _resolve(path);
    try {
      final response = await _sendRaw('GET', uri, headers: headers);
      return await _parseResponseEnvelope<T>(response, fromJson);
    } on TokenRefreshedException {
      final retryResponse = await _sendRaw('GET', uri, headers: headers);
      return await _parseResponseEnvelope<T>(retryResponse, fromJson);
    }
  }

  /// POST request returning full ApiResponseEnvelope
  Future<ApiResponseEnvelope<T>> postEnvelope<T>(
    String path, {
    Map<String, String>? headers,
    Object? body,
    required T Function(dynamic) fromJson,
  }) async {
    final uri = _resolve(path);
    try {
      final response = await _sendRaw(
        'POST',
        uri,
        headers: headers,
        body: body,
      );
      return await _parseResponseEnvelope<T>(response, fromJson);
    } on TokenRefreshedException {
      final retryResponse = await _sendRaw(
        'POST',
        uri,
        headers: headers,
        body: body,
      );
      return await _parseResponseEnvelope<T>(retryResponse, fromJson);
    }
  }

  /// PUT request returning full ApiResponseEnvelope
  Future<ApiResponseEnvelope<T>> putEnvelope<T>(
    String path, {
    Map<String, String>? headers,
    Object? body,
    required T Function(dynamic) fromJson,
  }) async {
    final uri = _resolve(path);
    try {
      final response = await _sendRaw('PUT', uri, headers: headers, body: body);
      return await _parseResponseEnvelope<T>(response, fromJson);
    } on TokenRefreshedException {
      final retryResponse = await _sendRaw(
        'PUT',
        uri,
        headers: headers,
        body: body,
      );
      return await _parseResponseEnvelope<T>(retryResponse, fromJson);
    }
  }

  /// GET request returning PaginatedResponseEnvelope
  Future<PaginatedResponseEnvelope<T>> getPaginated<T>(
    String path, {
    Map<String, String>? headers,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final uri = _resolve(path);
    try {
      final response = await _sendRaw('GET', uri, headers: headers);
      return await _parsePaginatedResponse<T>(response, fromJson);
    } on TokenRefreshedException {
      final retryResponse = await _sendRaw('GET', uri, headers: headers);
      return await _parsePaginatedResponse<T>(retryResponse, fromJson);
    }
  }

  /// Internal method: sends request and returns unwrapped data
  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    try {
      final response = await _sendRaw(
        method,
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );
      return await _handleResponse(response);
    } on TokenRefreshedException {
      final retryResponse = await _sendRaw(
        method,
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );
      return await _handleResponse(retryResponse);
    }
  }

  // Maximum number of additional attempts after the first one.
  static const int _maxRetries = 1;

  /// Internal method: sends request and returns raw ApiResponse.
  ///
  /// Automatically retries up to [_maxRetries] times on 5xx responses and
  /// transient network/timeout errors using exponential back-off (1 s, 2 s).
  /// 4xx client errors (except 401, which is handled by TokenRefreshInterceptor)
  /// are NOT retried.
  Future<ApiResponse> _sendRaw(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    if (!await _networkInfo.isConnected) {
      throw ServerException('No network connection');
    }

    final resolvedHeaders = await _buildHeaders(headers);

    final req = ApiRequest(
      method: method,
      uri: uri,
      headers: resolvedHeaders,
      body: body,
    );

    await _notifyRequest(req);

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      if (attempt > 0) {
        // Exponential back-off: 1 s on first retry, 2 s on second.
        await Future.delayed(Duration(seconds: attempt));
      }

      try {
        final response = await _dispatch(
          method,
          uri,
          req.headers,
          body,
        ).timeout(timeout ?? ApiConfig.receiveTimeout);

        final apiResponse = ApiResponse(
          statusCode: response.statusCode,
          uri: uri,
          body: response.body,
        );

        // Retry on 5xx server errors (except 501 Not Implemented) while
        // attempts remain. On the final attempt, return the response as-is
        // so that _handleResponse can produce the right exception upstream.
        if (response.statusCode >= 500 &&
            response.statusCode != 501 &&
            attempt < _maxRetries) {
          continue;
        }

        await _notifyResponse(apiResponse);
        return apiResponse;
      } catch (e) {
        // Non-retriable exceptions — propagate immediately without retry.
        if (e is ApiErrorException ||
            e is UnauthorizedException ||
            e is TokenRefreshedException) {
          await _notifyError(
            ApiError(method: method, uri: uri, cause: e, message: e.toString()),
          );
          rethrow;
        }

        // Retriable error (timeout, network failure, etc.) — try again if
        // attempts remain.
        if (attempt < _maxRetries) continue;

        // Final attempt: notify observers and propagate the error.
        await _notifyError(
          ApiError(method: method, uri: uri, cause: e, message: e.toString()),
        );
        if (e is ServerException) rethrow;
        throw ServerException('$method ${uri.path} failed: $e');
      }
    }

    // Unreachable — the loop always returns or throws on the last iteration.
    throw AssertionError('_sendRaw: unexpected exit from retry loop');
  }

  Future<http.Response> _dispatch(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) {
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
      case 'PUT':
        return _client.put(uri, headers: headers, body: jsonEncode(body ?? {}));
      case 'PATCH':
        return _client.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
      case 'DELETE':
        return _client.delete(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
      default:
        throw ServerException('Unsupported method $method');
    }
  }

  Future<Map<String, dynamic>> _handleResponse(ApiResponse response) async {
    final statusCode = response.statusCode;

    // Check for error status codes
    if (statusCode < 200 || statusCode >= 300) {
      await _handleErrorResponse(response);
    }

    if (response.body.isEmpty) return <String, dynamic>{};

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      // If it's an envelope, unwrap the data
      if (decoded.containsKey('data')) {
        final data = decoded['data'];
        // Handle both Map and List data
        if (data is Map<String, dynamic>) {
          return data;
        } else if (data is List) {
          // Return the full envelope if data is a list
          return decoded;
        }
        return decoded;
      }
      return decoded;
    }
    return {'data': decoded};
  }

  /// Parse error response and throw ApiErrorException
  Future<void> _handleErrorResponse(ApiResponse response) async {
    // Handle 401 Unauthorized
    if (response.statusCode == 401) {
      // Try to refresh token if callback is provided
      if (_onUnauthorized != null) {
        final refreshed = await _onUnauthorized();
        if (refreshed) {
          // Token was refreshed, caller should retry
          throw TokenRefreshedException();
        }
      }
      throw UnauthorizedException('Unauthorized');
    }

    if (response.body.isEmpty) {
      throw ServerException(
        'Request ${response.uri.path} failed with status ${response.statusCode}',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
        final errorEnvelope = ErrorResponseEnvelope.fromJson(decoded);
        throw ApiErrorException(errorEnvelope);
      }
    } catch (e) {
      if (e is ApiErrorException) rethrow;
      if (e is UnauthorizedException) rethrow;
      if (e is TokenRefreshedException) rethrow;
      // If parsing fails, throw generic error
    }

    throw ServerException(
      'Request ${response.uri.path} failed with status ${response.statusCode}',
    );
  }

  /// Parse ApiResponseEnvelope from response
  Future<ApiResponseEnvelope<T>> _parseResponseEnvelope<T>(
    ApiResponse response,
    T Function(dynamic) fromJson,
  ) async {
    final statusCode = response.statusCode;

    if (statusCode < 200 || statusCode >= 300) {
      await _handleErrorResponse(response);
    }

    if (response.body.isEmpty) {
      throw ServerException('Empty response body');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return ApiResponseEnvelope.fromJson(decoded, fromJson);
  }

  /// Parse PaginatedResponseEnvelope from response
  Future<PaginatedResponseEnvelope<T>> _parsePaginatedResponse<T>(
    ApiResponse response,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final statusCode = response.statusCode;

    if (statusCode < 200 || statusCode >= 300) {
      await _handleErrorResponse(response);
    }

    if (response.body.isEmpty) {
      throw ServerException('Empty response body');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return PaginatedResponseEnvelope.fromJson(decoded, fromJson);
  }

  Future<void> _notifyRequest(ApiRequest request) async {
    for (final i in _interceptors) {
      await i.onRequest(request);
    }
  }

  Future<void> _notifyResponse(ApiResponse response) async {
    for (final i in _interceptors) {
      await i.onResponse(response);
    }
  }

  Future<void> _notifyError(ApiError error) async {
    for (final i in _interceptors) {
      await i.onError(error);
    }
  }

  void close() {
    _client.close();
  }

  /// POST request returning a raw byte stream (for SSE / chunked responses).
  ///
  /// The caller is responsible for parsing the stream.  No retry logic is
  /// applied — SSE connections are long-lived and retrying mid-stream is not
  /// meaningful.
  Stream<List<int>> postStream(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async* {
    if (!await _networkInfo.isConnected) {
      throw ServerException('No network connection');
    }

    final uri = _resolve(path);
    final resolvedHeaders = await _buildHeaders(headers);
    // Tell the server we accept SSE
    resolvedHeaders['Accept'] = 'text/event-stream';

    final request = http.Request('POST', uri);
    request.headers.addAll(resolvedHeaders);
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamedResponse = await _client.send(request);

    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      final rawBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 401 && _onUnauthorized != null) {
        final refreshed = await _onUnauthorized();
        if (refreshed) {
          // Token refreshed — retry the stream once with the new token.
          final retryHeaders = await _buildHeaders(headers);
          retryHeaders['Accept'] = 'text/event-stream';
          final retryRequest = http.Request('POST', uri);
          retryRequest.headers.addAll(retryHeaders);
          if (body != null) retryRequest.body = jsonEncode(body);
          final retryResponse = await _client.send(retryRequest);
          if (retryResponse.statusCode >= 200 && retryResponse.statusCode < 300) {
            yield* retryResponse.stream;
            return;
          }
          final retryBody = await retryResponse.stream.bytesToString();
          throw ServerException(
            'POST stream ${uri.path} failed with status '
            '${retryResponse.statusCode}: $retryBody',
          );
        }
        throw UnauthorizedException('Unauthorized');
      }

      throw ServerException(
        'POST stream ${uri.path} failed with status '
        '${streamedResponse.statusCode}: $rawBody',
      );
    }

    yield* streamedResponse.stream;
  }
}
