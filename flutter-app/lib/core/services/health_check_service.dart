import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/api_config.dart';

/// Performs lightweight health checks against backend services.
class HealthCheckService {
  final ApiClient apiClient;

  HealthCheckService({required this.apiClient});

  /// The backend serves /health at its root, not under the /api/v1 prefix.
  static String get healthUrl =>
      Uri.parse(ApiConfig.baseUrl).replace(path: '/health').toString();

  /// Returns true if backend responds with 2xx at the given URL.
  Future<bool> ping({String? url}) async {
    try {
      await apiClient.get(url ?? healthUrl);
      return true;
    } catch (_) {
      return false;
    }
  }
}
