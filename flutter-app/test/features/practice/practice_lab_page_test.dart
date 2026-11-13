import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/practice/presentation/pages/practice_lab_page.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/vocabulary_di.dart'
    as vocab_di;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DiskAssetLoader extends AssetLoader {
  const _DiskAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _DataSource implements ProficiencyDataSource {
  _DataSource(this.profile);

  final ProficiencyProfile profile;

  @override
  Future<ProficiencyProfile> getProfile() async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StatsRepository extends Fake implements VocabularyRepository {
  _StatsRepository(this.due);

  final int due;

  @override
  Future<Either<Failure, Map<String, dynamic>>> getVocabularyStats() async =>
      Right({'due_for_review': due});
}

SkillScore _score(SkillType skill, {double score = 0, int exercises = 0}) =>
    SkillScore(
      skill: skill,
      score: score,
      confidence: exercises / 50,
      estimatedLevel: 'A1',
      accuracy: 0,
      trend: 'stable',
      exercisesCompleted: exercises,
    );

ProficiencyProfile _profile(List<SkillScore> scores) => ProficiencyProfile(
  userId: 'u1',
  assessedLevel: 'A2',
  overallScore: 0,
  totalXp: 0,
  skills: {for (final s in scores) s.skill: s},
  exercisesCompleted: 0,
  correctExercises: 0,
  accuracy: 0,
  lessonsCompleted: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpLab(
    WidgetTester tester,
    ProficiencyProfile profile, {
    double height = 812,
  }) async {
    tester.view.physicalSize = Size(375, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/i18n',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        useOnlyLangCode: true,
        assetLoader: const _DiskAssetLoader(),
        child: Builder(
          builder: (context) => ChangeNotifierProvider(
            create: (_) =>
                ProficiencyProvider(dataSource: _DataSource(profile)),
            child: MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: const PracticeLabPage(),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a new learner sees a hint, never a "0 focus skills" tile', (
    tester,
  ) async {
    // The backend zero-fills all six skills for a fresh account.
    await pumpLab(
      tester,
      _profile([for (final skill in SkillType.values) _score(skill)]),
    );

    expect(find.text('Focus skills'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(
      find.textContaining('your focus skills will show up here'),
      findsOneWidget,
    );
    // Starter cards are still offered — just not sold as a diagnosis.
    expect(find.text('Recommended practice'), findsOneWidget);
  });

  testWidgets('measured weaknesses show their real count', (tester) async {
    await pumpLab(
      tester,
      _profile([
        _score(SkillType.reading, score: 30, exercises: 9),
        _score(SkillType.writing), // unmeasured: must not be counted
      ]),
    );

    expect(find.text('Focus skills'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(
      find.textContaining('your focus skills will show up here'),
      findsNothing,
    );
  });

  group('vocabulary suggestion follows what is actually due', () {
    Future<void> pumpWithDue(WidgetTester tester, int due) async {
      vocab_di.getIt.registerSingleton<VocabularyRepository>(
        _StatsRepository(due),
      );
      addTearDown(() => vocab_di.getIt.reset());
      await pumpLab(
        tester,
        _profile([for (final s in SkillType.values) _score(s)]),
        height: 3000,
      );
    }

    testWidgets('words due: the review card is suggested and listed', (
      tester,
    ) async {
      await pumpWithDue(tester, 5);

      expect(find.text('Vocabulary'), findsNWidgets(2));
    });

    testWidgets('nothing due: the review card is only in the full list', (
      tester,
    ) async {
      await pumpWithDue(tester, 0);

      expect(find.text('Vocabulary'), findsOneWidget);
      expect(find.text('Recommended practice'), findsOneWidget);
    });
  });
}
