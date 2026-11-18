import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lexilingo_app/features/admin/core/network/api_client.dart';
import 'package:lexilingo_app/features/admin/core/storage/admin_session_store.dart';

class _Store implements AdminSessionStore {
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<bool> refresh() async => false;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

/// What an admin screen sent the server.
class SentRequest {
  SentRequest(this.method, this.path, this.query, this.body);
  final String method, path;
  final Map<String, dynamic> query;
  final dynamic body;
}

/// An [ApiClient] whose server is [handler]: it gets the method, path and
/// query and answers `(status, body)`. Every request is recorded in [sent].
class FakeAdminApi {
  FakeAdminApi(this.handler) {
    client = ApiClient.forTesting(
      store: _Store(),
      dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
        ..httpClientAdapter = _Adapter((o) async {
          sent.add(SentRequest(o.method, o.path, o.queryParameters, o.data));
          final (status, body) = await handler(
            o.method,
            o.path,
            o.queryParameters,
          );
          return jsonResponse(status, body);
        }),
    );
  }

  final Future<(int, Object)> Function(
    String method,
    String path,
    Map<String, dynamic> query,
  )
  handler;
  late final ApiClient client;
  final sent = <SentRequest>[];

  Iterable<SentRequest> where(String method, String path) =>
      sent.where((r) => r.method == method && r.path == path);
}
