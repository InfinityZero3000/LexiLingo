import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/vocabulary_di.dart'
    as vocab_di;

/// Due-vocabulary count for Today's Plan. Shared by the home-screen card and
/// the full plan page so the fetch+parse logic isn't duplicated (and doesn't
/// drift) between the two — each screen still fires its own request since
/// they're independently mounted, but there is exactly one place that knows
/// how to read `due_for_review` out of the stats response.
Future<int?> fetchDueVocabularyCount() async {
  final result = await vocab_di
      .getIt<VocabularyRepository>()
      .getVocabularyStats();

  return result.fold((_) => null, (stats) => stats['due_for_review'] as int? ?? 0);
}
