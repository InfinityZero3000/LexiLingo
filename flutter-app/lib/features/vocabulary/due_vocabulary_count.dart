import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/vocabulary_di.dart'
    as vocab_di;

/// Words due for review, or null when the stats request failed. The one place
/// that knows how to read `due_for_review` out of the stats response — Today's
/// Plan and the Practice Lab both ask it rather than parsing the map twice.
Future<int?> fetchDueVocabularyCount() async {
  final result = await vocab_di
      .getIt<VocabularyRepository>()
      .getVocabularyStats();

  return result.fold(
    (_) => null,
    (stats) => stats['due_for_review'] as int? ?? 0,
  );
}
