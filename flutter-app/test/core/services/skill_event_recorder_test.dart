import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/skill_event_recorder.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';

void main() {
  group('vocabConceptId', () {
    test('matches the backend slug convention', () {
      // Mirrors _vocab_concept_id in backend-service/app/crud/vocabulary.py.
      // A mismatch would create a second concept for the same word rather
      // than failing loudly, so this is the check that keeps them together.
      expect(vocabConceptId('Hotel Room'), 'vocab:hotel_room');
      expect(vocabConceptId('  departure   lounge  '), 'vocab:departure_lounge');
      expect(vocabConceptId('Run'), 'vocab:run');
    });

    test('returns null for a word with nothing in it', () {
      expect(vocabConceptId(''), isNull);
      expect(vocabConceptId('   '), isNull);
    });
  });

  group('normalizeCefrLevel', () {
    test('accepts the six CEFR bands in any casing', () {
      expect(normalizeCefrLevel('a1'), 'A1');
      expect(normalizeCefrLevel('C2'), 'C2');
      expect(normalizeCefrLevel(' b2 '), 'B2');
    });

    test('falls back to B1 rather than sending something the API rejects', () {
      expect(normalizeCefrLevel(null), 'B1');
      expect(normalizeCefrLevel(''), 'B1');
      expect(normalizeCefrLevel('intermediate'), 'B1');
    });
  });

  group('SkillEventRecorder', () {
    test('does nothing when there is no result to send', () async {
      // No ProficiencyDataSource is registered here, so this also proves the
      // recorder stays silent instead of throwing when DI is not set up.
      await const SkillEventRecorder().record([]);
    });

    test('swallows a failing write instead of surfacing it', () async {
      await const SkillEventRecorder().record([
        ExerciseResultData(
          exerciseType: 'news_quiz',
          skill: SkillType.reading,
          difficultyLevel: 'B1',
          isCorrect: true,
          score: 100,
        ),
      ]);
    });
  });

  group('ExerciseResultData.toJson', () {
    test('omits concept_id unless one was given', () {
      final without = ExerciseResultData(
        exerciseType: 'news_quiz',
        skill: SkillType.reading,
        difficultyLevel: 'B1',
        isCorrect: true,
        score: 100,
      ).toJson();
      expect(without.containsKey('concept_id'), isFalse);

      final with_ = ExerciseResultData(
        exerciseType: 'pronunciation_word',
        skill: SkillType.speaking,
        difficultyLevel: 'B1',
        isCorrect: false,
        score: 42,
        conceptId: 'vocab:hotel_room',
      ).toJson();
      expect(with_['concept_id'], 'vocab:hotel_room');
      expect(with_['skill'], 'speaking');
    });
  });
}
