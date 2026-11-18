import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/features/admin/core/network/api_client.dart';
import 'package:lexilingo_app/features/admin/core/storage/admin_session_store.dart';
import 'package:lexilingo_app/features/admin/features/system/data/system_repository.dart';
import 'package:lexilingo_app/features/admin/features/system_logs/data/logs_repository.dart';

class _Store implements AdminSessionStore {
  @override
  Future<String?> accessToken() async => 't';
  @override
  Future<bool> refresh() async => false;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final (int, Object?) Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = respond(options);
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

ApiClient _client(_Adapter adapter) => ApiClient.forTesting(
  store: _Store(),
  dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = adapter,
);

void main() {
  test(
    'audit page reads {logs,total} and sends per_page paging + filters',
    () async {
      final adapter = _Adapter(
        (_) => (
          200,
          {
            'logs': [
              {'action': 'login', 'resource_type': 'user', 'created_at': 'now'},
            ],
            'total': 41,
            'page': 2,
            'per_page': 30,
          },
        ),
      );
      final repo = LogsRepository(api: _client(adapter));
      final page = await repo.fetchPage(const PageRequest(index: 1, size: 30), {
        'action': 'login',
        'resource_type': null,
      });
      expect(page.items.single.action, 'login');
      expect(page.total, 41);
      final q = adapter.requests.single.queryParameters;
      expect(q['page'], '2');
      expect(q['per_page'], '30');
      expect(q['action'], 'login');
      expect(q.containsKey('resource_type'), isFalse);
    },
  );

  test('ops calls pass days and every call is a GET', () async {
    final adapter = _Adapter((_) => (200, {'status': 'ok'}));
    final repo = SystemRepository(api: _client(adapter));
    final s = await repo.ops('product-events', days: 7);
    expect(s.scalars.single.value, 'ok');
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/admin/ops/product-events');
    expect(adapter.requests.single.queryParameters['days'], 7);
  });

  test('kpis unwrap the `kpis` key; roles read a raw list', () async {
    final adapter = _Adapter(
      (o) => o.path.endsWith('/kpis')
          ? (
              200,
              {
                'kpis': {'total_users': 5},
              },
            )
          : (
              200,
              [
                {'slug': 'admin', 'name': 'Admin', 'level': 1},
              ],
            ),
    );
    final repo = SystemRepository(api: _client(adapter));
    expect((await repo.kpis()).scalars.single.value, '5');
    final roles = await repo.roles();
    expect((roles.single.slug, roles.single.level), ('admin', 1));
  });

  test('a 403 reaches the caller as a DioException', () async {
    final adapter = _Adapter(
      (_) => (403, {'detail': 'Permission required: ops:read'}),
    );
    final repo = SystemRepository(api: _client(adapter));
    expect(repo.ops('celery'), throwsA(isA<DioException>()));
  });
}
