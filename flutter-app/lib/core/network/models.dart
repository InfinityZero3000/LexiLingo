/// Request model passed to interceptors.
class ApiRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Object? body;

  ApiRequest({required this.method, required this.uri, required this.headers, this.body});
}

/// Response model passed to interceptors.
class ApiResponse {
  final int statusCode;
  final Uri uri;
  final String body;

  ApiResponse({required this.statusCode, required this.uri, required this.body});

  String get bodyPreview => body.length > 500 ? '${body.substring(0, 500)}…' : body;
}

/// Error model passed to interceptors.
class ApiError {
  final String method;
  final Uri uri;
  final Object cause;
  final String message;

  ApiError({required this.method, required this.uri, required this.cause, required this.message});
}
