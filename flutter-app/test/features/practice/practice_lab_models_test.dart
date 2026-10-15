import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/practice/presentation/widgets/practice_lab_models.dart';

void main() {
  group('Practice Lab models', () {
    test('buildPracticeLabItems returns skill labs plus mistake notebook', () {
      final items = buildPracticeLabItems();

      expect(items, hasLength(7));
      expect(items.map((item) => item.destination), [
        PracticeLabDestination.vocabularyReview,
        PracticeLabDestination.voicePractice,
        PracticeLabDestination.podcast,
        PracticeLabDestination.news,
        PracticeLabDestination.games,
        PracticeLabDestination.mistakeNotebook,
        PracticeLabDestination.lexi,
      ]);
      expect(items.map((item) => item.skill), [
        SkillType.vocabulary,
        SkillType.speaking,
        SkillType.listening,
        SkillType.reading,
        SkillType.grammar,
        SkillType.reading,
        SkillType.writing,
      ]);
    });

    test('marks weakest skills as recommended', () {
      final items = buildPracticeLabItems(
        weakestSkills: const [
          SkillScore(
            skill: SkillType.grammar,
            score: 32,
            confidence: 0.8,
            estimatedLevel: 'A2',
            accuracy: 0.64,
            trend: 'stable',
            exercisesCompleted: 12,
          ),
          SkillScore(
            skill: SkillType.writing,
            score: 41,
            confidence: 0.7,
            estimatedLevel: 'B1',
            accuracy: 0.68,
            trend: 'declining',
            exercisesCompleted: 9,
          ),
        ],
      );

      final recommended = items
          .where((item) => item.recommended)
          .map((item) => item.skill)
          .toList();

      expect(recommended, [SkillType.grammar, SkillType.writing]);
    });

    test(
      'recommendedPracticeItems falls back to first items without scores',
      () {
        final items = buildPracticeLabItems();

        final recommended = recommendedPracticeItems(items: items);

        expect(recommended, hasLength(2));
        expect(recommended.map((item) => item.skill), [
          SkillType.vocabulary,
          SkillType.speaking,
        ]);
      },
    );

    test('no catalog item is premium-only', () {
      // Writing used to carry premiumOnly here, but it only navigated to
      // Lexi chat, which is free from its own tab anyway — locking entry was
      // a dead end a free learner could just route around. The real premium
      // perk moved server-side: a daily message cap on Lexi chat.
      final items = buildPracticeLabItems();

      expect(items.where((item) => item.premiumOnly), isEmpty);
    });
  });
}
