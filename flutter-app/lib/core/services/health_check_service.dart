import 'package:lexilingo_app/core/network/api_client.dart';

/// Performs lightweight health checks against backend services.
class HealthCheckService {
  final ApiClient apiClient;

  HealthCheckService({required this.apiClient});

  /// Returns true if backend responds with 2xx at the given path.
  Future<bool> ping({String path = '/health'}) async {
    try {
      await apiClient.get(path);
      return true;
    } catch (_) {
      return false;
    }
  }
}
