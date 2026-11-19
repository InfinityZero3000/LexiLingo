import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/network_info.dart';

class _FakeConnectivity implements Connectivity {
  _FakeConnectivity(this.result);
  final List<ConnectivityResult> result;
  int checks = 0;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    checks += 1;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('web never blocks a request on navigator.onLine reporting offline', () async {
    final connectivity = _FakeConnectivity([ConnectivityResult.none]);
    final info = NetworkInfoImpl(connectivity: connectivity, isWeb: true);

    expect(await info.isConnected, isTrue);
    expect(connectivity.checks, 0);
  });

  test('native still reports offline when every interface is down', () async {
    final info = NetworkInfoImpl(
      connectivity: _FakeConnectivity([ConnectivityResult.none]),
      isWeb: false,
    );

    expect(await info.isConnected, isFalse);
  });

  test('native with no resolvable probe host is offline', () async {
    final info = NetworkInfoImpl(
      connectivity: _FakeConnectivity([ConnectivityResult.wifi]),
      probeHosts: const ['nonexistent.invalid'],
      dnsCheckTimeout: const Duration(milliseconds: 500),
      isWeb: false,
    );

    expect(await info.isConnected, isFalse);
  });
}
