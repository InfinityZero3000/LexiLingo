import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/entitlement_service.dart';
import 'package:lexilingo_app/core/services/premium_status.dart';

class _FakeApi implements ApiClient {
  Object? error;
  Map<String, dynamic> body = const {};

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    if (error != null) throw error!;
    return body;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeApi api;

  setUp(() async {
    await sl.reset();
    api = _FakeApi();
    sl.registerSingleton<EntitlementService>(
      EntitlementService(apiClient: api),
    );
  });

  tearDown(() => sl.reset());

  test(
    'offline: falls back to the SDK cache and a paying learner stays unlocked',
    () async {
      api.error = Exception('offline');
      expect(await resolvePremium(isPremiumFromSdk: () async => true), isTrue);
    },
  );

  test('offline and SDK says free: locked', () async {
    api.error = Exception('offline');
    expect(await resolvePremium(isPremiumFromSdk: () async => false), isFalse);
  });

  test('backend answer wins over the SDK', () async {
    api.body = {'active': false};
    expect(await resolvePremium(isPremiumFromSdk: () async => true), isFalse);
    api.body = {'active': true};
    expect(await resolvePremium(isPremiumFromSdk: () async => false), isTrue);
  });
}
