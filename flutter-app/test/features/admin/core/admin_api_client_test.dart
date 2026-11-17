import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/core/network/admin_api_error.dart';
import 'package:lexilingo_app/features/admin/core/network/api_client.dart';
import 'package:lexilingo_app/features/admin/core/storage/admin_session_store.dart';

class _Store implements AdminSessionStore {
  String? access = 'old-access';
  String? refresh = 'refresh-1';
  int clears = 0;

  @override
  Future<String?> accessToken() async => access;
  @override
  Future<String?> refreshToken() async => refresh;
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    clears++;
    access = null;
    refresh = null;
  }
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

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  late _Store store;
  late int refreshCalls;
  late List<String?> seenAuth;

  ApiClient build({bool refreshOk = true}) {
    refreshCalls = 0;
    seenAuth = [];
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))
      ..httpClientAdapter = _Adapter((o) async {
        final auth = o.headers['Authorization'] as String?;
        seenAuth.add(auth);
        if (auth == 'Bearer new-access') {
          return _json(200, {
            'data': {'ok': true},
          });
        }
        return _json(401, {'detail': 'expired'});
      });
    final refreshDio = Dio()
      ..httpClientAdapter = _Adapter((o) async {
        refreshCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (!refreshOk) return _json(401, {'detail': 'bad'});
        return _json(200, {
          'data': {'access_token': 'new-access', 'refresh_token': 'refresh-2'},
        });
      });
    return ApiClient.forTesting(store: store, dio: dio, refreshDio: refreshDio);
  }

  setUp(() => store = _Store());

  test('three concurrent 401s share one refresh and all retry', () async {
    final api = build();
    final results = await Future.wait([
      api.get('/a'),
      api.get('/b'),
      api.get('/c'),
    ]);
    expect(refreshCalls, 1);
    expect(results.every((r) => (r['data'] as Map)['ok'] == true), isTrue);
    expect(store.refresh, 'refresh-2');
    expect(store.access, 'new-access');
  });

  test(
    'a refresh that fails clears the session and surfaces the 401',
    () async {
      final api = build(refreshOk: false);
      await expectLater(
        api.get('/a'),
        throwsA(
          isA<DioException>().having(
            (e) => AdminApiError.from(e).kind,
            'kind',
            AdminErrorKind.unauthorized,
          ),
        ),
      );
      expect(store.clears, 1);
      expect(store.access, isNull);
    },
  );

  test('getData removes the envelope', () async {
    final api = build();
    store.access = 'new-access';
    expect(await api.getData('/a'), {'ok': true});
  });

  test('a request is retried once, not forever', () async {
    final api = build();
    final dio = api.dio;
    dio.httpClientAdapter = _Adapter((o) async => _json(401, {'detail': 'no'}));
    await expectLater(api.get('/a'), throwsA(isA<DioException>()));
    expect(refreshCalls, 1);
  });

  group('AdminApiError', () {
    DioException status(int code, [Object? body]) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: code,
        data: body,
      ),
    );

    test('403 and 503 are ordinary states', () {
      expect(AdminApiError.from(status(403)).isForbidden, isTrue);
      expect(AdminApiError.from(status(503)).isFeatureOff, isTrue);
      expect(AdminApiError.from(status(500)).kind, AdminErrorKind.server);
      expect(AdminApiError.from(status(404)).kind, AdminErrorKind.notFound);
    });

    test('a 4xx keeps the server reason; a timeout is a network error', () {
      final e = AdminApiError.from(status(409, {'detail': 'Slug taken'}));
      expect(e.message.resolve(), 'Slug taken');
      final timeout = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(AdminApiError.from(timeout).isNetwork, isTrue);
    });
  });
}
