import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/utils/app_logger.dart';

/// Asks the server for replies the learner could tap after Lexi's question.
/// Never throws: no suggestions is a normal outcome, not an error.
class LexiReplySuggester {
  final ApiClient apiClient;
  LexiReplySuggester({required this.apiClient});

  Future<List<String>> suggest(String lexiText) async {
    try {
      final json = await apiClient.post(
        '/lexi/suggest-replies',
        body: {'text': lexiText},
      );
      final data = json['data'] ?? json;
      final options = data is Map ? data['options'] : null;
      return [
        if (options is List)
          for (final o in options)
            if (o is String && o.trim().isNotEmpty) o.trim(),
      ];
    } catch (e) {
      AppLogger.warn('LexiReplySuggester', 'failed: $e');
      return const [];
    }
  }
}
