import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../error/exceptions.dart';
import 'api_config.dart';
import 'interceptors/api_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'models.dart';
import 'network_info.dart';

/// HTTP client with basic interceptors, connectivity check, and error mapping.
class ApiClient {
  final http.Client _client;
  final String _baseUrl;
  final List<ApiInterceptor> _interceptors;
  final NetworkInfo _networkInfo;

  ApiClient({
    http.Client? client,
    String? baseUrl,
    List<ApiInterceptor>? interceptors,
    NetworkInfo? networkInfo,
    bool enableLogging = true,
  })  : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceAll(RegExp(r'/+$'), ''),
        _interceptors = [
          if (enableLogging) LoggingInterceptor(),
          ...?interceptors,
        ],
        _networkInfo = networkInfo ?? NetworkInfoImpl();

  Map<String, String> _buildHeaders(Map<String, String>? headers) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    };
  }

  Uri _resolve(String path) {
    if (path.startsWith('http')) return Uri.parse(path);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalizedPath');
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? headers}) async {
    final uri = _resolve(path);
    return _send('GET', uri, headers: headers);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final uri = _resolve(path);
    return _send('POST', uri, headers: headers, body: body);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    if (!await _networkInfo.isConnected) {
      throw ServerException('No network connection');
    }

    final req = ApiRequest(
      method: method,
      uri: uri,
      headers: _buildHeaders(headers),
      body: body,
    );

    await _notifyRequest(req);

    try {
      final response = await _dispatch(method, uri, req.headers, body)
          .timeout(ApiConfig.receiveTimeout);
      final apiResponse = ApiResponse(
        statusCode: response.statusCode,
        uri: uri,
        body: response.body,
      );
      await _notifyResponse(apiResponse);
      return _handleResponse(apiResponse);
    } catch (e) {
      await _notifyError(ApiError(
        method: method,
        uri: uri,
        cause: e,
        message: e.toString(),
      ));
      if (e is ServerException) rethrow;
      throw ServerException('$method ${uri.path} failed: $e');
    }
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
      default:
        throw ServerException('Unsupported method $method');
    }
  }

  Map<String, dynamic> _handleResponse(ApiResponse response) {
    final statusCode = response.statusCode;
    if (statusCode >= 200 && statusCode < 300) {
      if (response.body.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    }
    throw ServerException(
      'Request ${response.uri.path} failed with status $statusCode',
    );
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
}
