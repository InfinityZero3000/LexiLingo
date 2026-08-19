import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/practice/presentation/widgets/practice_lab_models.dart';

/// Regressions for the four recommendation defects found in the skill-loop
/// audit. Each one made "practise this next" mean something other than what it
/// claimed.
SkillScore _score(
  SkillType skill, {
  double score = 0,
  int exercises = 0,
  double confidence = 0,
}) =>
    SkillScore(
      skill: skill,
      score: score,
      confidence: confidence,
      estimatedLevel: 'A1',
      accuracy: 0,
      trend: 'stable',
      exercisesCompleted: exercises,
    );

ProficiencyProfile _profile(List<SkillScore> scores) => ProficiencyProfile(
      userId: 'u1',
      assessedLevel: 'A1',
      overallScore: 0,
      totalXp: 0,
      skills: {for (final s in scores) s.skill: s},
      exercisesCompleted: 0,
      correctExercises: 0,
      accuracy: 0,
      lessonsCompleted: 0,
    );

void main() {
  group('weakest skills need evidence', () {
    test('a learner who has practised nothing has no weakest skill', () {
      // The backend returns all six skills zero-filled, so sorting by score
      // used to hand back whichever two came first — insertion order dressed
      // up as a diagnosis.
      final profile = _profile([
        for (final skill in SkillType.values) _score(skill),
      ]);

      expect(profile.weakestSkills, isEmpty);
      expect(profile.unmeasuredSkills, hasLength(6));
    });

    test('an unmeasured zero never outranks a measured low score', () {
      final profile = _profile([
        _score(SkillType.reading, score: 35, exercises: 12, confidence: 0.24),
        _score(SkillType.writing), // never practised
        _score(SkillType.speaking, score: 20, exercises: 5, confidence: 0.10),
      ]);

      expect(
        profile.weakestSkills.map((s) => s.skill),
        [SkillType.speaking, SkillType.reading],
        reason: 'writing has no evidence, so it cannot be called a weakness',
      );
    });

    test('on a tie the better-measured score wins', () {
      final profile = _profile([
        _score(SkillType.reading, score: 40, exercises: 2, confidence: 0.04),
        _score(SkillType.grammar, score: 40, exercises: 45, confidence: 0.90),
      ]);

      expect(profile.weakestSkills.first.skill, SkillType.grammar);
    });

    test('strongest skills apply the same rule', () {
      final profile = _profile([
        _score(SkillType.reading, score: 70, exercises: 20, confidence: 0.40),
        _score(SkillType.listening), // unmeasured
      ]);

      expect(profile.strongestSkills.map((s) => s.skill), [SkillType.reading]);
    });
  });

  group('recommendations', () {
    test('a free learner is never handed a locked card', () {
      // Writing is premium-only and is almost always among the weakest, so the
      // first thing a free learner saw under "recommended" was a padlock.
      final items = buildPracticeLabItems(
        weakestSkills: [
          _score(SkillType.writing, score: 10, exercises: 4),
          _score(SkillType.reading, score: 30, exercises: 9),
        ],
      );

      final free = recommendedPracticeItems(items: items, hasPremium: false);
      expect(free.any((item) => item.premiumOnly), isFalse);
      expect(free, isNotEmpty);

      final paid = recommendedPracticeItems(items: items, hasPremium: true);
      expect(paid.any((item) => item.premiumOnly), isTrue);
    });

    test('two cards of the same skill never fill both slots', () {
      // The mistake notebook is also tagged `reading`, so a reading weakness
      // could return two routes to the same practice and hide the second
      // weakness entirely.
      final items = buildPracticeLabItems(
        weakestSkills: [
          _score(SkillType.reading, score: 30, exercises: 9),
          _score(SkillType.grammar, score: 35, exercises: 11),
        ],
      );

      final picked = recommendedPracticeItems(items: items);
      expect(picked, hasLength(2));
      expect(
        picked.map((item) => item.skill).toSet(),
        hasLength(2),
        reason: 'each recommendation should offer a different skill',
      );
    });

    test('falls back to distinct starter cards when nothing is measured', () {
      final picked = recommendedPracticeItems(
        items: buildPracticeLabItems(),
        hasPremium: false,
      );

      expect(picked, hasLength(2));
      expect(picked.map((item) => item.skill).toSet(), hasLength(2));
      expect(picked.any((item) => item.premiumOnly), isFalse);
    });
  });

  group('one skill-to-destination table', () {
    test('every skill resolves, and writing goes to Lexi', () {
      // Today's Plan kept a second copy of this and had already drifted:
      // writing pointed at games there and at Lexi here.
      for (final skill in SkillType.values) {
        expect(practiceDestinationForSkill(skill), isNotNull);
      }
      expect(
        practiceDestinationForSkill(SkillType.writing),
        PracticeLabDestination.lexi,
      );
      expect(
        practiceDestinationForSkill(SkillType.listening),
        PracticeLabDestination.podcast,
      );
    });

    test('each card sits on the destination the shared table names', () {
      for (final item in buildPracticeLabItems()) {
        if (item.destination == PracticeLabDestination.mistakeNotebook) continue;
        expect(
          item.destination,
          practiceDestinationForSkill(item.skill),
          reason: '${item.skill} card should match the shared mapping',
        );
      }
    });
  });
}
