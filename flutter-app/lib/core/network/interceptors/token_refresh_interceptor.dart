import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import '../models.dart';
import '../response_models.dart';
import 'api_interceptor.dart';

/// Interceptor that automatically refreshes tokens on 401 errors
/// Implements token refresh logic with retry mechanism
class TokenRefreshInterceptor implements ApiInterceptor {
  final Future<String?> Function() getRefreshToken;
  final Future<void> Function(String accessToken, String refreshToken) saveTokens;
  final Future<void> Function() onRefreshFailed;
  final String refreshTokenEndpoint;
  final http.Client client;

  bool _isRefreshing = false;
  final List<Completer<void>> _pendingRequests = [];

  TokenRefreshInterceptor({
    required this.getRefreshToken,
    required this.saveTokens,
    required this.onRefreshFailed,
    this.refreshTokenEndpoint = '/auth/refresh',
    http.Client? client,
  }) : client = client ?? http.Client();

  @override
  Future<void> onRequest(ApiRequest request) async {
    // Wait if token refresh is in progress
    if (_isRefreshing) {
      final completer = Completer<void>();
      _pendingRequests.add(completer);
      await completer.future;
    }
  }

  @override
  Future<void> onResponse(ApiResponse response) async {
    // Check if response is 401 Unauthorized
    if (response.statusCode == 401) {
      await _handleUnauthorized(response);
    }
  }

  @override
  Future<void> onError(ApiError error) async {
    // No special error handling needed here
  }

  Future<void> _handleUnauthorized(ApiResponse response) async {
    // If already refreshing, don't trigger another refresh
    if (_isRefreshing) return;

    _isRefreshing = true;

    try {
      // Try to parse error to check if it's AUTH_EXPIRED
      if (response.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
            final errorEnvelope = ErrorResponseEnvelope.fromJson(decoded);
            
            // Only refresh token if error code is AUTH_EXPIRED or AUTH_INVALID
            if (errorEnvelope.error.code != ErrorCodes.authExpired &&
                errorEnvelope.error.code != ErrorCodes.authInvalid) {
              return; // Don't refresh for other auth errors
            }
          }
        } catch (_) {
          // If parsing fails, proceed with refresh attempt
        }
      }

      // Get refresh token
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) {
        await onRefreshFailed();
        return;
      }

      // Call refresh token endpoint
      final newTokens = await _refreshTokens(refreshToken);
      
      // Save new tokens
      await saveTokens(newTokens['access_token']!, newTokens['refresh_token']!);

      // Resume pending requests
      _resumePendingRequests();
    } catch (e) {
      // Refresh failed, trigger logout
      await onRefreshFailed();
      _cancelPendingRequests();
    } finally {
      _isRefreshing = false;
    }
  }

  Future<Map<String, String>> _refreshTokens(String refreshToken) async {
    final uri = Uri.parse('${_getBaseUrl()}$refreshTokenEndpoint');
    
    final response = await client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );

    if (response.statusCode != 200) {
      throw Exception('Token refresh failed with status ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    
    // Parse response - backend returns tokens directly, not wrapped in 'data'
    final data = decoded.containsKey('data') 
        ? decoded['data'] as Map<String, dynamic>
        : decoded;
    
    return {
      'access_token': data['access_token'] as String,
      'refresh_token': data['refresh_token'] as String,
    };
  }

  String _getBaseUrl() {
    return ApiConfig.baseUrl;
  }

  void _resumePendingRequests() {
    for (final completer in _pendingRequests) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _pendingRequests.clear();
  }

  void _cancelPendingRequests() {
    for (final completer in _pendingRequests) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Token refresh failed'));
      }
    }
    _pendingRequests.clear();
  }
}
