import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/envelope.dart';

class PublicStats {
  const PublicStats({required this.learners, required this.lessonsToday});

  final int learners;
  final int lessonsToday;
}

typedef PublicStatsLoader = Future<PublicStats?> Function();

/// Real community numbers for the welcome page; null means "show nothing".
class PublicStatsService {
  PublicStatsService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<PublicStats?> fetch() async {
    try {
      final body = unwrapEnvelope(await _apiClient.get('/public/stats'));
      if (body is! Map || body['show'] != true) return null;
      final learners = body['learners'];
      final lessons = body['lessons_completed_today'];
      if (learners is! num || lessons is! num) return null;
      return PublicStats(
        learners: learners.toInt(),
        lessonsToday: lessons.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}
