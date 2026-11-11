import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/health_check_service.dart';

class _RecordingClient extends ApiClient {
  _RecordingClient({this.fail = false}) : super(enableLogging: false);

  final bool fail;
  String? requested;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    requested = path;
    if (fail) throw Exception('down');
    return {'status': 'healthy'};
  }
}

void main() {
  test(
    'pings /health at the server root, outside the /api/v1 prefix',
    () async {
      final client = _RecordingClient();

      expect(await HealthCheckService(apiClient: client).ping(), isTrue);

      final uri = Uri.parse(client.requested!);
      expect(uri.path, '/health');
      expect(uri.hasAuthority, isTrue);
    },
  );

  test('reports false when the backend is unreachable', () async {
    final service = HealthCheckService(apiClient: _RecordingClient(fail: true));

    expect(await service.ping(), isFalse);
  });
}
