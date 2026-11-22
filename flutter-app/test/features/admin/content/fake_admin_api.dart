import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lexilingo_app/features/admin/core/network/api_client.dart';
import 'package:lexilingo_app/features/admin/core/storage/admin_session_store.dart';

class _Store implements AdminSessionStore {
  @override
  Future<String?> accessToken() async => 'token';
  @override
  Future<bool> refresh() async => false;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final (int, Object) Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (status, body) = handler(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// An admin [ApiClient] whose server is [handler]; every request it sees is
/// kept in [requests].
class FakeAdminApi {
  FakeAdminApi(this._handler) {
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))
      ..httpClientAdapter = _Adapter((o) {
        requests.add(o);
        return _handler(o);
      });
    client = ApiClient.forTesting(store: _Store(), dio: dio);
  }

  final (int, Object) Function(RequestOptions) _handler;
  final requests = <RequestOptions>[];
  late final ApiClient client;
}
