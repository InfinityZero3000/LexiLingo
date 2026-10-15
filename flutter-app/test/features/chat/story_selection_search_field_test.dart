import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/chat/domain/entities/story.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/story_repository.dart';
import 'package:lexilingo_app/features/chat/presentation/pages/story_selection_page.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/story_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StoryRepositoryStub implements StoryRepository {
  @override
  Future<Either<Failure, List<StoryListItem>>> getStories({
    String? category,
    DifficultyLevel? difficultyLevel,
    int limit = 100,
  }) async => const Right([]);

  @override
  Future<Either<Failure, List<String>>> getCategories() async =>
      const Right([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('topic search content is vertically centered', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _StoryRepositoryStub();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => StoryProvider(repository: repository),
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const StorySelectionPage(),
        ),
      ),
    );
    await tester.pump();

    final fieldCenter = tester.getCenter(find.byType(TextField));
    final iconCenter = tester.getCenter(find.byIcon(Icons.search));
    final hintCenter = tester.getCenter(find.text('storySelection.searchHint'));

    final centers = 'field: $fieldCenter, icon: $iconCenter, hint: $hintCenter';
    expect(iconCenter.dy, closeTo(fieldCenter.dy, 0.5), reason: centers);
    expect(hintCenter.dy, closeTo(fieldCenter.dy, 0.5), reason: centers);
  });
}
