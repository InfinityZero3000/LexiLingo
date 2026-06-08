import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';

void main() {
  // ── GameType ────────────────────────────────────────────────────────────────

  group('GameType', () {
    test('apiKey returns correct snake_case values', () {
      expect(GameType.wordScramble.apiKey, 'word_scramble');
      expect(GameType.fillBlank.apiKey, 'fill_blank');
      expect(GameType.matching.apiKey, 'matching');
      expect(GameType.spellingBee.apiKey, 'spelling_bee');
      expect(GameType.grammarQuiz.apiKey, 'grammar_quiz');
      expect(GameType.hangman.apiKey, 'hangman');
    });

    test('displayName returns non-empty string for all types', () {
      for (final type in GameType.values) {
        expect(
          type.displayName.isNotEmpty,
          isTrue,
          reason: '${type.name} displayName should not be empty',
        );
      }
    });

    test('icon returns non-empty string for all types', () {
      for (final type in GameType.values) {
        expect(
          type.icon,
          isNotNull,
          reason: '${type.name} icon should not be null',
        );
      }
    });

    test('description returns non-empty string for all types', () {
      for (final type in GameType.values) {
        expect(
          type.description.isNotEmpty,
          isTrue,
          reason: '${type.name} description should not be empty',
        );
      }
    });
  });

  // ── GameWord ─────────────────────────────────────────────────────────────────

  group('GameWord', () {
    final sampleJson = <String, dynamic>{
      'word_id': 'uuid-001',
      'word': 'adventure',
      'definition': 'An exciting experience',
      'hint': 'Something exciting',
      'example_sentence': 'Life is a great adventure.',
      'ipa_pronunciation': '/ədˈventʃər/',
      'cefr_level': 'B1',
      'category': 'travel',
      'xp_value': 15,
      'vietnamese_translation': 'cuộc phiêu lưu',
      'synonyms': ['expedition', 'journey'],
    };

    test('fromJson parses all fields', () {
      final word = GameWord.fromJson(sampleJson);
      expect(word.wordId, 'uuid-001');
      expect(word.word, 'adventure');
      expect(word.definition, 'An exciting experience');
      expect(word.hint, 'Something exciting');
      expect(word.exampleSentence, 'Life is a great adventure.');
      expect(word.ipaPronunciation, '/ədˈventʃər/');
      expect(word.cefrLevel, 'B1');
      expect(word.category, 'travel');
      expect(word.xpValue, 15);
      expect(word.vietnameseTranslation, 'cuộc phiêu lưu');
      expect(word.synonyms, ['expedition', 'journey']);
    });

    test('fromJson uses id field as fallback for word_id', () {
      final json = <String, dynamic>{'id': 'fallback-id', 'word': 'test'};
      final word = GameWord.fromJson(json);
      expect(word.wordId, 'fallback-id');
    });

    test('fromJson defaults for missing optional fields', () {
      final word = GameWord.fromJson(<String, dynamic>{
        'word_id': '1',
        'word': 'cat',
      });
      expect(word.cefrLevel, 'A1');
      expect(word.category, 'general');
      expect(word.xpValue, 5);
      expect(word.synonyms, isNull);
    });

    test('toJson roundtrip preserves required fields', () {
      final word = GameWord.fromJson(sampleJson);
      final json = word.toJson();
      expect(json['word_id'], 'uuid-001');
      expect(json['word'], 'adventure');
      expect(json['cefr_level'], 'B1');
      expect(json['xp_value'], 15);
    });

    test('copyWith returns new instance with changed fields', () {
      final word = GameWord.fromJson(sampleJson);
      final updated = word.copyWith(xpValue: 20, cefrLevel: 'B2');
      expect(updated.xpValue, 20);
      expect(updated.cefrLevel, 'B2');
      expect(updated.word, word.word); // unchanged
    });
  });

  // ── ScrambleWord ─────────────────────────────────────────────────────────────

  group('ScrambleWord', () {
    final sampleJson = <String, dynamic>{
      'word_id': 'w001',
      'word': 'CAT',
      'shuffled_letters': ['T', 'A', 'C'],
      'hint': 'A pet animal',
      'definition': 'A small furry animal',
      'ipa_pronunciation': '/kæt/',
      'xp_value': 5,
      'letter_count': 3,
      'cefr_level': 'A1',
    };

    test('fromJson parses shuffled_letters', () {
      final word = ScrambleWord.fromJson(sampleJson);
      expect(word.shuffledLetters, ['T', 'A', 'C']);
    });

    test('fromJson accepts legacy letters field', () {
      final json = <String, dynamic>{
        'word': 'CAT',
        'letters': ['C', 'T', 'A'],
        'hint': '',
      };
      final word = ScrambleWord.fromJson(json);
      expect(word.shuffledLetters, ['C', 'T', 'A']);
    });

    test('fromJson defaults letter_count to word length', () {
      final json = <String, dynamic>{
        'word': 'hello',
        'shuffled_letters': <dynamic>['H', 'E', 'L', 'L', 'O'],
      };
      final word = ScrambleWord.fromJson(json);
      expect(word.letterCount, 5);
    });

    test('toJson roundtrip', () {
      final word = ScrambleWord.fromJson(sampleJson);
      final json = word.toJson();
      expect(json['word'], 'CAT');
      expect(json['shuffled_letters'], ['T', 'A', 'C']);
    });
  });

  // ── WordScrambleGame ──────────────────────────────────────────────────────────

  group('WordScrambleGame', () {
    test('fromJson parses words list', () {
      final json = <String, dynamic>{
        'cefr_level': 'A2',
        'timer_seconds': 60,
        'base_xp_per_word': 10,
        'streak_bonus_threshold': 3,
        'words': <dynamic>[
          <String, dynamic>{
            'word_id': '1',
            'word': 'CAT',
            'shuffled_letters': <dynamic>['T', 'C', 'A'],
            'hint': '',
          },
        ],
      };
      final game = WordScrambleGame.fromJson(json);
      expect(game.cefrLevel, 'A2');
      expect(game.timerSeconds, 60);
      expect(game.words.length, 1);
      expect(game.words.first.word, 'CAT');
    });

    test('fromJson with empty words', () {
      final game = WordScrambleGame.fromJson(<String, dynamic>{
        'cefr_level': 'B1',
        'timer_seconds': 60,
        'words': <dynamic>[],
      });
      expect(game.words, isEmpty);
    });
  });

  // ── MatchingPair ─────────────────────────────────────────────────────────────

  group('MatchingPair', () {
    test('fromJson parses fields', () {
      final json = <String, dynamic>{
        'word_id': 'p1',
        'word': 'cat',
        'match_text': 'A small furry pet animal',
        'variant': 'definition',
      };
      final pair = MatchingPair.fromJson(json);
      expect(pair.wordId, 'p1');
      expect(pair.matchText, 'A small furry pet animal');
      expect(pair.variant, 'definition');
    });

    test('fromJson accepts match field as fallback for match_text', () {
      final json = <String, dynamic>{
        'word': 'dog',
        'match': 'kitten',
        'variation': 'synonym',
      };
      final pair = MatchingPair.fromJson(json);
      expect(pair.matchText, 'kitten');
      expect(pair.variant, 'synonym');
    });

    test('toJson roundtrip', () {
      const pair = MatchingPair(
        wordId: 'p2',
        word: 'apple',
        matchText: 'quả táo',
        variant: 'vietnamese',
      );
      final json = pair.toJson();
      expect(json['word_id'], 'p2');
      expect(json['match_text'], 'quả táo');
      expect(json['variant'], 'vietnamese');
    });
  });

  // ── SpellingBeeWord ───────────────────────────────────────────────────────────

  group('SpellingBeeWord', () {
    final sampleJson = <String, dynamic>{
      'word_id': 'sb1',
      'word': 'knowledge',
      'ipa_pronunciation': '/ˈnɒlɪdʒ/',
      'definition': 'Information acquired through experience',
      'example_sentence': 'Knowledge is power.',
      'xp_value': 15,
      'audio_url': null,
    };

    test('fromJson parses all fields', () {
      final word = SpellingBeeWord.fromJson(sampleJson);
      expect(word.word, 'knowledge');
      expect(word.ipaPronunciation, '/ˈnɒlɪdʒ/');
      expect(word.xpValue, 15);
      expect(word.audioUrl, isNull);
    });

    test('fromJson accepts xp_full as fallback for xp_value', () {
      final json = <String, dynamic>{'word': 'test', 'xp_full': 20};
      final word = SpellingBeeWord.fromJson(json);
      expect(word.xpValue, 20);
    });

    test('fromJson accepts tts_url as fallback for audio_url', () {
      final json = <String, dynamic>{
        'word': 'test',
        'tts_url': 'https://example.com/tts.mp3',
      };
      final word = SpellingBeeWord.fromJson(json);
      expect(word.audioUrl, 'https://example.com/tts.mp3');
    });

    test('maxReplays defaults to 3', () {
      final word = SpellingBeeWord.fromJson(<String, dynamic>{'word': 'test'});
      expect(word.maxReplays, 3);
    });
  });

  // ── HangmanWord ───────────────────────────────────────────────────────────────

  group('HangmanWord', () {
    test('fromJson derives letter_count from word when missing', () {
      final word = HangmanWord.fromJson(<String, dynamic>{
        'word_id': 'h1',
        'word': 'school',
      });
      expect(word.letterCount, 6);
    });

    test('fromJson accepts base_xp as fallback for xp_value', () {
      final word = HangmanWord.fromJson(<String, dynamic>{
        'word': 'dog',
        'letter_count': 3,
        'base_xp': 25,
      });
      expect(word.xpValue, 25);
    });

    test('toJson includes letter_count', () {
      final word = HangmanWord.fromJson(<String, dynamic>{
        'word_id': 'h2',
        'word': 'apple',
        'letter_count': 5,
        'category': 'food',
      });
      expect(word.toJson()['letter_count'], 5);
    });
  });

  // ── FillBlankQuestion ─────────────────────────────────────────────────────────

  group('FillBlankQuestion', () {
    final sampleJson = <String, dynamic>{
      'id': 1,
      'sentence': 'She ___ a teacher.',
      'options': <dynamic>['is', 'are', 'am', 'be'],
      'correct_answer': 'is',
      'grammar_tip': 'Use is with he/she/it.',
      'cefr_level': 'A1',
    };

    test('fromJson parses sentence and correct_answer', () {
      final q = FillBlankQuestion.fromJson(sampleJson);
      expect(q.sentence, 'She ___ a teacher.');
      expect(q.correctAnswer, 'is');
      expect(q.options.length, 4);
    });

    test('fromJson accepts question field as fallback for sentence', () {
      final q = FillBlankQuestion.fromJson(<String, dynamic>{
        'id': 2,
        'question': 'He ___ football.',
        'options': <dynamic>['plays', 'play'],
        'correct_answer': 'plays',
      });
      expect(q.sentence, 'He ___ football.');
    });

    test('fromJson derives correct_answer from correct_index when missing', () {
      final q = FillBlankQuestion.fromJson(<String, dynamic>{
        'id': 3,
        'sentence': 'I ___ from Vietnam.',
        'options': <dynamic>['am', 'is', 'are', 'be'],
        'correct_index': 0,
      });
      expect(q.correctAnswer, 'am');
    });

    test('id is stored as string', () {
      final q = FillBlankQuestion.fromJson(sampleJson);
      expect(q.id, isA<String>());
      expect(q.id, '1');
    });
  });

  // ── GrammarQuizQuestion ───────────────────────────────────────────────────────

  group('GrammarQuizQuestion', () {
    test('fromJson parses all fields', () {
      final json = <String, dynamic>{
        'id': 5,
        'question': 'She ___ a teacher.',
        'options': <dynamic>['is', 'are', 'am', 'be'],
        'correct_answer': 'is',
        'explanation': 'She is 3rd person singular.',
        'topic': 'to_be',
        'cefr_level': 'A1',
      };
      final q = GrammarQuizQuestion.fromJson(json);
      expect(q.question, 'She ___ a teacher.');
      expect(q.correctAnswer, 'is');
      expect(q.topic, 'to_be');
      expect(q.cefrLevel, 'A1');
    });

    test('fromJson derives correct_answer from correct_index', () {
      final jsonData = <String, dynamic>{
        'id': 1,
        'question': 'Test?',
        'options': <dynamic>['A', 'B', 'C', 'D'],
        'correct_index': 2,
      };
      final q = GrammarQuizQuestion.fromJson(jsonData);
      expect(q.correctAnswer, 'C');
    });
  });

  // ── GameResult ────────────────────────────────────────────────────────────────

  group('GameResult', () {
    GameResult makeResult({required int correct, required int total}) {
      return GameResult(
        gameType: GameType.grammarQuiz,
        cefrLevel: 'B1',
        score: correct * 10,
        totalQuestions: total,
        correctAnswers: correct,
        xpEarned: correct * 5,
        durationSeconds: 120,
      );
    }

    test('accuracy returns 100.0 when all correct', () {
      final result = makeResult(correct: 10, total: 10);
      expect(result.accuracy, 100.0);
    });

    test('accuracy returns 0.0 when no questions answered', () {
      final result = makeResult(correct: 0, total: 0);
      expect(result.accuracy, 0.0);
    });

    test('accuracy is percentage not fraction', () {
      final result = makeResult(correct: 6, total: 10);
      expect(result.accuracy, 60.0);
    });

    test('stars returns 3 for 90+ accuracy', () {
      final result = makeResult(correct: 9, total: 10);
      expect(result.stars, 3);
    });

    test('stars returns 2 for 60-89 accuracy', () {
      final result = makeResult(correct: 6, total: 10);
      expect(result.stars, 2);
    });

    test('stars returns 1 for below 60 accuracy', () {
      final result = makeResult(correct: 4, total: 10);
      expect(result.stars, 1);
    });

    test('perfect score gives 3 stars', () {
      final result = makeResult(correct: 10, total: 10);
      expect(result.stars, 3);
    });
  });

  // ── XPTransaction ─────────────────────────────────────────────────────────────

  group('XPTransaction', () {
    test('fromJson parses all fields', () {
      final json = <String, dynamic>{
        'id': 'tx-001',
        'amount': 20,
        'source': 'game',
        'source_detail': 'word_scramble',
        'leveled_up': false,
        'created_at': '2024-01-15T10:00:00.000',
      };
      final tx = XPTransaction.fromJson(json);
      expect(tx.id, 'tx-001');
      expect(tx.amount, 20);
      expect(tx.source, 'game');
      expect(tx.sourceDetail, 'word_scramble');
      expect(tx.leveledUp, false);
      expect(tx.createdAt.year, 2024);
    });

    test('toJson roundtrip', () {
      final now = DateTime(2024, 3, 15, 12, 0, 0);
      final tx = XPTransaction(
        id: 'tx-002',
        amount: 15,
        source: 'news',
        createdAt: now,
      );
      final json = tx.toJson();
      expect(json['id'], 'tx-002');
      expect(json['amount'], 15);
      expect(json['source'], 'news');
    });
  });

  // ── XPProfile ─────────────────────────────────────────────────────────────────

  group('XPProfile', () {
    test('fromJson parses all required fields', () {
      final json = <String, dynamic>{
        'user_id': 'user-123',
        'total_xp': 350,
        'numeric_level': 4,
        'level_progress_percent': 50.0,
        'xp_for_next_level': 100,
        'current_xp_in_level': 50,
        'daily_xp_today': 120,
        'daily_cap_remaining': 380,
        'streak_days': 7,
        'best_streak': 14,
        'recent_transactions': <dynamic>[],
      };
      final profile = XPProfile.fromJson(json);
      expect(profile.userId, 'user-123');
      expect(profile.totalXp, 350);
      expect(profile.numericLevel, 4);
      expect(profile.streakDays, 7);
      expect(profile.bestStreak, 14);
      expect(profile.recentTransactions, isEmpty);
    });

    test('fromJson parses nested recent_transactions', () {
      final json = <String, dynamic>{
        'user_id': 'u1',
        'total_xp': 100,
        'numeric_level': 1,
        'recent_transactions': <dynamic>[
          <String, dynamic>{
            'id': 'tx-1',
            'amount': 20,
            'source': 'game',
            'leveled_up': false,
            'created_at': '2024-01-01T00:00:00',
          },
        ],
      };
      final profile = XPProfile.fromJson(json);
      expect(profile.recentTransactions.length, 1);
      expect(profile.recentTransactions.first.source, 'game');
    });
  });

  // ── XPAwardResult ─────────────────────────────────────────────────────────────

  group('XPAwardResult', () {
    test('fromJson parses all fields', () {
      final json = <String, dynamic>{
        'xp_awarded': 30,
        'base_xp': 20,
        'multiplier': 1.5,
        'new_total_xp': 130,
        'daily_xp_today': 30,
        'daily_cap_remaining': 470,
        'leveled_up': false,
        'old_level': 1,
        'new_level': 1,
        'level_progress_percent': 30.0,
        'xp_for_next_level': 70,
        'current_xp_in_level': 30,
        'streak_days': 7,
        'message': '+30 XP earned!',
      };
      final result = XPAwardResult.fromJson(json);
      expect(result.xpAwarded, 30);
      expect(result.multiplier, 1.5);
      expect(result.leveledUp, false);
      expect(result.currentXpInLevel, 30);
      expect(result.streakDays, 7);
      expect(result.message, '+30 XP earned!');
    });

    test('fromJson defaults multiplier to 1.0', () {
      final result = XPAwardResult.fromJson(<String, dynamic>{
        'xp_awarded': 10,
        'base_xp': 10,
        'new_total_xp': 10,
        'old_level': 1,
        'new_level': 1,
      });
      expect(result.multiplier, 1.0);
    });
  });

  // ── LeaderboardEntry ──────────────────────────────────────────────────────────

  group('LeaderboardEntry', () {
    test('fromJson parses rank and user info', () {
      final json = <String, dynamic>{
        'rank': 1,
        'user_id': 'u-001',
        'username': 'champion',
        'total_xp': 5000,
        'numeric_level': 10,
        'weekly_xp': 300,
        'is_current_user': true,
      };
      final entry = LeaderboardEntry.fromJson(json);
      expect(entry.rank, 1);
      expect(entry.username, 'champion');
      expect(entry.totalXp, 5000);
      expect(entry.isCurrentUser, true);
    });

    test('fromJson defaults isCurrentUser to false', () {
      final entry = LeaderboardEntry.fromJson(<String, dynamic>{
        'rank': 5,
        'user_id': 'u2',
        'username': 'player',
        'total_xp': 1000,
      });
      expect(entry.isCurrentUser, false);
    });
  });

  group('Canonical game API contracts', () {
    test('MatchingGame parses canonical variant and definitions column', () {
      final game = MatchingGame.fromJson(<String, dynamic>{
        'cefr_level': 'A1',
        'variant': 'definition',
        'timer_seconds': 60,
        'time_bonus_threshold': 0.5,
        'base_xp': 10,
        'pairs': <dynamic>[
          <String, dynamic>{
            'word_id': 'p1',
            'word': 'cat',
            'match_text': 'A small furry animal',
            'variant': 'definition',
          },
        ],
        'words_column': <dynamic>['cat'],
        'definitions_column': <dynamic>['A small furry animal'],
      });

      expect(game.variant, 'definition');
      expect(game.definitionsColumn, ['A small furry animal']);
    });

    test('MatchingGameData parses string columns from the API', () {
      final game = MatchingGameData.fromJson(<String, dynamic>{
        'pairs': <dynamic>[
          <String, dynamic>{
            'word_id': 'p1',
            'word': 'cat',
            'match_text': 'A small furry animal',
            'variant': 'definition',
          },
        ],
        'words_column': <dynamic>['cat'],
        'definitions_column': <dynamic>['A small furry animal'],
      });

      expect(game.wordsColumn, ['cat']);
      expect(game.definitionsColumn, ['A small furry animal']);
    });

    test('GrammarQuizGame keeps the string correct answer', () {
      final game = GrammarQuizGame.fromJson(<String, dynamic>{
        'cefr_level': 'A1',
        'topic': 'to_be',
        'timer_seconds_per_question': 12,
        'total_xp': 10,
        'questions': <dynamic>[
          <String, dynamic>{
            'id': 1,
            'question': 'She ___ a teacher.',
            'options': <dynamic>['are', 'is', 'am', 'be'],
            'correct_answer': 'is',
            'explanation': 'Use is with she.',
            'topic': 'to_be',
            'cefr_level': 'A1',
          },
        ],
      });

      expect(game.questions.single.correctAnswer, 'is');
    });

    test('HangmanGame parses server-provided hints and XP config', () {
      final game = HangmanGame.fromJson(<String, dynamic>{
        'word_id': 'h1',
        'word': 'cat',
        'letter_count': 3,
        'category': 'animals',
        'cefr_level': 'A1',
        'base_xp': 8,
        'max_lives': 6,
        'hints': <String, dynamic>{
          'hint1_free': 'A common pet',
          'hint2_xp_cost': 2,
          'hint2_definition': 'A small furry animal',
          'hint3_xp_cost': 3,
        },
      });

      expect(game.baseXp, 8);
      expect(game.maxLives, 6);
      expect(game.hints.hint1Free, 'A common pet');
      expect(game.hints.hint2Definition, 'A small furry animal');
    });
  });
}
