/// Game domain entities for the Games feature — XP System & mini-games.
///
/// All entities are plain Dart classes with copyWith, fromJson, and toJson.
// ignore: depend_on_referenced_packages
import 'package:flutter/material.dart';

// ── Game Types ────────────────────────────────────────────────────────────────

enum GameType {
  wordScramble,
  fillBlank,
  matching,
  spellingBee,
  grammarQuiz,
  hangman;

  String get apiKey => switch (this) {
        GameType.wordScramble => 'word_scramble',
        GameType.fillBlank => 'fill_blank',
        GameType.matching => 'matching',
        GameType.spellingBee => 'spelling_bee',
        GameType.grammarQuiz => 'grammar_quiz',
        GameType.hangman => 'hangman',
      };

  String get displayName => switch (this) {
        GameType.wordScramble => 'Word Scramble',
        GameType.fillBlank => 'Fill in the Blank',
        GameType.matching => 'Matching Game',
        GameType.spellingBee => 'Spelling Bee',
        GameType.grammarQuiz => 'Grammar Quiz',
        GameType.hangman => 'Hangman',
      };

  IconData get icon => switch (this) {
        GameType.wordScramble => Icons.sort_by_alpha_rounded,
        GameType.fillBlank => Icons.edit_note_rounded,
        GameType.matching => Icons.compare_arrows_rounded,
        GameType.spellingBee => Icons.volume_up_rounded,
        GameType.grammarQuiz => Icons.menu_book_rounded,
        GameType.hangman => Icons.extension_rounded,
      };

  String get description => switch (this) {
        GameType.wordScramble => 'Arrange scrambled letters to form words',
        GameType.fillBlank => 'Choose the correct word to complete the sentence',
        GameType.matching => 'Match words with their definitions',
        GameType.spellingBee => 'Listen and type the word you hear',
        GameType.grammarQuiz => 'Test your grammar knowledge',
        GameType.hangman => 'Guess the word letter by letter',
      };
}

// ── GameWord ──────────────────────────────────────────────────────────────────

/// A vocabulary word fetched from the database for use in any game.
class GameWord {
  final String wordId;
  final String word;
  final String definition;
  final String? hint;
  final String? exampleSentence;
  final String? ipaPronunciation;
  final String cefrLevel;
  final String category;
  final int xpValue;
  final String? vietnameseTranslation;
  final List<String>? synonyms;

  const GameWord({
    required this.wordId,
    required this.word,
    required this.definition,
    this.hint,
    this.exampleSentence,
    this.ipaPronunciation,
    this.cefrLevel = 'A1',
    this.category = 'general',
    this.xpValue = 5,
    this.vietnameseTranslation,
    this.synonyms,
  });

  factory GameWord.fromJson(Map<String, dynamic> json) {
    return GameWord(
      wordId: json['word_id'] as String? ?? json['id'] as String? ?? '',
      word: json['word'] as String? ?? '',
      definition: json['definition'] as String? ?? '',
      hint: json['hint'] as String?,
      exampleSentence: json['example_sentence'] as String?,
      ipaPronunciation: json['ipa_pronunciation'] as String?,
      cefrLevel: json['cefr_level'] as String? ?? 'A1',
      category: json['category'] as String? ?? 'general',
      xpValue: json['xp_value'] as int? ?? 5,
      vietnameseTranslation: json['vietnamese_translation'] as String?,
      synonyms: (json['synonyms'] as List<dynamic>?)
          ?.map((s) => s as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'word_id': wordId,
        'word': word,
        'definition': definition,
        if (hint != null) 'hint': hint,
        if (exampleSentence != null) 'example_sentence': exampleSentence,
        if (ipaPronunciation != null) 'ipa_pronunciation': ipaPronunciation,
        'cefr_level': cefrLevel,
        'category': category,
        'xp_value': xpValue,
        if (vietnameseTranslation != null)
          'vietnamese_translation': vietnameseTranslation,
        if (synonyms != null) 'synonyms': synonyms,
      };

  GameWord copyWith({
    String? wordId,
    String? word,
    String? definition,
    String? hint,
    String? exampleSentence,
    String? ipaPronunciation,
    String? cefrLevel,
    String? category,
    int? xpValue,
    String? vietnameseTranslation,
    List<String>? synonyms,
  }) {
    return GameWord(
      wordId: wordId ?? this.wordId,
      word: word ?? this.word,
      definition: definition ?? this.definition,
      hint: hint ?? this.hint,
      exampleSentence: exampleSentence ?? this.exampleSentence,
      ipaPronunciation: ipaPronunciation ?? this.ipaPronunciation,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      category: category ?? this.category,
      xpValue: xpValue ?? this.xpValue,
      vietnameseTranslation:
          vietnameseTranslation ?? this.vietnameseTranslation,
      synonyms: synonyms ?? this.synonyms,
    );
  }
}

// ── Word Scramble ─────────────────────────────────────────────────────────────

/// A word used in the word-scramble game, with pre-shuffled letters.
class ScrambleWord {
  final String wordId;
  final String word;
  /// Shuffled letters the player rearranges (field: shuffled_letters | letters).
  final List<String> shuffledLetters;
  /// Correct letter order — present when the backend sends it.
  final List<String> correctOrder;
  final String hint;
  final String definition;
  /// IPA pronunciation (field: ipa_pronunciation | ipa).
  final String? ipaPronunciation;
  final int xpValue;
  final int letterCount;
  final String cefrLevel;

  const ScrambleWord({
    required this.wordId,
    required this.word,
    required this.shuffledLetters,
    this.correctOrder = const [],
    this.hint = '',
    this.definition = '',
    this.ipaPronunciation,
    this.xpValue = 10,
    this.letterCount = 0,
    this.cefrLevel = 'A1',
  });

  factory ScrambleWord.fromJson(Map<String, dynamic> json) {
    // Accept both 'shuffled_letters' (new API) and 'letters' (legacy).
    final rawLetters =
        json['shuffled_letters'] as List<dynamic>? ??
        json['letters'] as List<dynamic>? ??
        const [];
    final word = json['word'] as String? ?? '';
    return ScrambleWord(
      wordId: json['word_id'] as String? ?? json['id'] as String? ?? '',
      word: word,
      shuffledLetters: rawLetters.map((l) => l as String).toList(),
      correctOrder: (json['correct_order'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      hint: json['hint'] as String? ?? '',
      definition: json['definition'] as String? ?? '',
      ipaPronunciation:
          json['ipa_pronunciation'] as String? ?? json['ipa'] as String?,
      xpValue: json['xp_value'] as int? ?? 10,
      letterCount: json['letter_count'] as int? ?? word.length,
      cefrLevel: json['cefr_level'] as String? ?? 'A1',
    );
  }

  Map<String, dynamic> toJson() => {
        'word_id': wordId,
        'word': word,
        'shuffled_letters': shuffledLetters,
        'correct_order': correctOrder,
        'hint': hint,
        'definition': definition,
        if (ipaPronunciation != null) 'ipa_pronunciation': ipaPronunciation,
        'xp_value': xpValue,
        'letter_count': letterCount,
        'cefr_level': cefrLevel,
      };

  ScrambleWord copyWith({
    String? wordId,
    String? word,
    List<String>? shuffledLetters,
    List<String>? correctOrder,
    String? hint,
    String? definition,
    String? ipaPronunciation,
    int? xpValue,
    int? letterCount,
    String? cefrLevel,
  }) {
    return ScrambleWord(
      wordId: wordId ?? this.wordId,
      word: word ?? this.word,
      shuffledLetters: shuffledLetters ?? this.shuffledLetters,
      correctOrder: correctOrder ?? this.correctOrder,
      hint: hint ?? this.hint,
      definition: definition ?? this.definition,
      ipaPronunciation: ipaPronunciation ?? this.ipaPronunciation,
      xpValue: xpValue ?? this.xpValue,
      letterCount: letterCount ?? this.letterCount,
      cefrLevel: cefrLevel ?? this.cefrLevel,
    );
  }
}

/// Full word-scramble session returned by the backend.
class WordScrambleGame {
  final String cefrLevel;
  final int timerSeconds;
  final int baseXpPerWord;
  final int streakBonusThreshold;
  final List<ScrambleWord> words;

  const WordScrambleGame({
    required this.cefrLevel,
    required this.timerSeconds,
    required this.baseXpPerWord,
    required this.streakBonusThreshold,
    required this.words,
  });

  factory WordScrambleGame.fromJson(Map<String, dynamic> json) {
    return WordScrambleGame(
      cefrLevel: json['cefr_level'] as String? ?? 'A2',
      timerSeconds: json['timer_seconds'] as int? ?? 60,
      baseXpPerWord: json['base_xp_per_word'] as int? ?? 10,
      streakBonusThreshold: json['streak_bonus_threshold'] as int? ?? 3,
      words: (json['words'] as List<dynamic>?)
              ?.map((w) => ScrambleWord.fromJson(w as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'cefr_level': cefrLevel,
        'timer_seconds': timerSeconds,
        'base_xp_per_word': baseXpPerWord,
        'streak_bonus_threshold': streakBonusThreshold,
        'words': words.map((w) => w.toJson()).toList(),
      };

  WordScrambleGame copyWith({
    String? cefrLevel,
    int? timerSeconds,
    int? baseXpPerWord,
    int? streakBonusThreshold,
    List<ScrambleWord>? words,
  }) {
    return WordScrambleGame(
      cefrLevel: cefrLevel ?? this.cefrLevel,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      baseXpPerWord: baseXpPerWord ?? this.baseXpPerWord,
      streakBonusThreshold: streakBonusThreshold ?? this.streakBonusThreshold,
      words: words ?? this.words,
    );
  }
}

// ── Matching Game ─────────────────────────────────────────────────────────────

/// A single word-definition (or word-synonym, word-translation) pair for the
/// matching game.
///
/// [variant] is one of: 'definition' | 'synonym' | 'vietnamese'.
/// Field aliases: word_id|id, match_text|match, variant|variation.
class MatchingPair {
  final String wordId;
  final String word;
  /// The definition, synonym, or Vietnamese text the player matches to [word].
  final String matchText;
  /// Variant type: 'definition' | 'synonym' | 'vietnamese'.
  final String variant;

  const MatchingPair({
    required this.wordId,
    required this.word,
    required this.matchText,
    this.variant = 'definition',
  });

  factory MatchingPair.fromJson(Map<String, dynamic> json) {
    return MatchingPair(
      wordId: json['word_id'] as String? ?? json['id'] as String? ?? '',
      word: json['word'] as String? ?? '',
      matchText: json['match_text'] as String? ?? json['match'] as String? ?? '',
      variant:
          json['variant'] as String? ??
          json['variation'] as String? ??
          'definition',
    );
  }

  Map<String, dynamic> toJson() => {
        'word_id': wordId,
        'word': word,
        'match_text': matchText,
        'variant': variant,
      };

  MatchingPair copyWith({
    String? wordId,
    String? word,
    String? matchText,
    String? variant,
  }) {
    return MatchingPair(
      wordId: wordId ?? this.wordId,
      word: word ?? this.word,
      matchText: matchText ?? this.matchText,
      variant: variant ?? this.variant,
    );
  }
}

/// Full response payload from GET /games/matching.
///
/// [wordsColumn] contains the word cards; [definitionsColumn] contains
/// the shuffled match cards the player pairs with words.
class MatchingGameData {
  final List<MatchingPair> wordsColumn;
  final List<MatchingPair> definitionsColumn;

  const MatchingGameData({
    required this.wordsColumn,
    required this.definitionsColumn,
  });

  factory MatchingGameData.fromJson(Map<String, dynamic> json) {
    return MatchingGameData(
      wordsColumn: (json['words_column'] as List<dynamic>? ?? [])
          .map((p) => MatchingPair.fromJson(p as Map<String, dynamic>))
          .toList(),
      definitionsColumn:
          (json['definitions_column'] as List<dynamic>? ?? [])
              .map((p) =>
                  MatchingPair.fromJson(p as Map<String, dynamic>))
              .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'words_column': wordsColumn.map((p) => p.toJson()).toList(),
        'definitions_column':
            definitionsColumn.map((p) => p.toJson()).toList(),
      };

  MatchingGameData copyWith({
    List<MatchingPair>? wordsColumn,
    List<MatchingPair>? definitionsColumn,
  }) {
    return MatchingGameData(
      wordsColumn: wordsColumn ?? this.wordsColumn,
      definitionsColumn: definitionsColumn ?? this.definitionsColumn,
    );
  }
}

/// Full matching-game session returned by the backend (includes config).
class MatchingGame {
  final String cefrLevel;
  final String variation;
  final int timerSeconds;
  final double timeBonusThreshold;
  final int baseXp;
  final List<MatchingPair> pairs;
  final List<String> wordsColumn;
  final List<String> matchesColumn; // Shuffled

  const MatchingGame({
    required this.cefrLevel,
    required this.variation,
    required this.timerSeconds,
    required this.timeBonusThreshold,
    required this.baseXp,
    required this.pairs,
    required this.wordsColumn,
    required this.matchesColumn,
  });

  factory MatchingGame.fromJson(Map<String, dynamic> json) {
    return MatchingGame(
      cefrLevel: json['cefr_level'] as String? ?? 'B1',
      variation: json['variation'] as String? ?? 'definition',
      timerSeconds: json['timer_seconds'] as int? ?? 45,
      timeBonusThreshold:
          (json['time_bonus_threshold'] as num?)?.toDouble() ?? 0.5,
      baseXp: json['base_xp'] as int? ?? 18,
      pairs: (json['pairs'] as List<dynamic>?)
              ?.map((p) => MatchingPair.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      wordsColumn: (json['words_column'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      matchesColumn: (json['matches_column'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'cefr_level': cefrLevel,
        'variation': variation,
        'timer_seconds': timerSeconds,
        'time_bonus_threshold': timeBonusThreshold,
        'base_xp': baseXp,
        'pairs': pairs.map((p) => p.toJson()).toList(),
        'words_column': wordsColumn,
        'matches_column': matchesColumn,
      };

  MatchingGame copyWith({
    String? cefrLevel,
    String? variation,
    int? timerSeconds,
    double? timeBonusThreshold,
    int? baseXp,
    List<MatchingPair>? pairs,
    List<String>? wordsColumn,
    List<String>? matchesColumn,
  }) {
    return MatchingGame(
      cefrLevel: cefrLevel ?? this.cefrLevel,
      variation: variation ?? this.variation,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      timeBonusThreshold: timeBonusThreshold ?? this.timeBonusThreshold,
      baseXp: baseXp ?? this.baseXp,
      pairs: pairs ?? this.pairs,
      wordsColumn: wordsColumn ?? this.wordsColumn,
      matchesColumn: matchesColumn ?? this.matchesColumn,
    );
  }
}

// ── Spelling Bee ──────────────────────────────────────────────────────────────

/// A word used in the spelling bee game.
///
/// Field aliases: word_id|id, ipa_pronunciation|ipa, audio_url|tts_url.
class SpellingBeeWord {
  final String wordId;
  final String word;
  final String? ipaPronunciation;
  final String definition;
  final String? exampleSentence;
  final int xpValue;
  final String? audioUrl;
  /// Full-credit XP (when backend sends split values).
  final int? xpFull;
  /// Partial-credit XP.
  final int? xpPartial;
  final int maxReplays;

  const SpellingBeeWord({
    required this.wordId,
    required this.word,
    this.ipaPronunciation,
    this.definition = '',
    this.exampleSentence,
    this.xpValue = 10,
    this.audioUrl,
    this.xpFull,
    this.xpPartial,
    this.maxReplays = 3,
  });

  factory SpellingBeeWord.fromJson(Map<String, dynamic> json) {
    return SpellingBeeWord(
      wordId: json['word_id'] as String? ?? json['id'] as String? ?? '',
      word: json['word'] as String? ?? '',
      ipaPronunciation:
          json['ipa_pronunciation'] as String? ?? json['ipa'] as String?,
      definition: json['definition'] as String? ?? '',
      exampleSentence: json['example_sentence'] as String?,
      xpValue: json['xp_value'] as int? ??
          json['xp_full'] as int? ??
          10,
      audioUrl:
          json['audio_url'] as String? ?? json['tts_url'] as String?,
      xpFull: json['xp_full'] as int?,
      xpPartial: json['xp_partial'] as int?,
      maxReplays: json['max_replays'] as int? ?? 3,
    );
  }

  Map<String, dynamic> toJson() => {
        'word_id': wordId,
        'word': word,
        if (ipaPronunciation != null) 'ipa_pronunciation': ipaPronunciation,
        'definition': definition,
        if (exampleSentence != null) 'example_sentence': exampleSentence,
        'xp_value': xpValue,
        if (audioUrl != null) 'audio_url': audioUrl,
        if (xpFull != null) 'xp_full': xpFull,
        if (xpPartial != null) 'xp_partial': xpPartial,
        'max_replays': maxReplays,
      };

  SpellingBeeWord copyWith({
    String? wordId,
    String? word,
    String? ipaPronunciation,
    String? definition,
    String? exampleSentence,
    int? xpValue,
    String? audioUrl,
    int? xpFull,
    int? xpPartial,
    int? maxReplays,
  }) {
    return SpellingBeeWord(
      wordId: wordId ?? this.wordId,
      word: word ?? this.word,
      ipaPronunciation: ipaPronunciation ?? this.ipaPronunciation,
      definition: definition ?? this.definition,
      exampleSentence: exampleSentence ?? this.exampleSentence,
      xpValue: xpValue ?? this.xpValue,
      audioUrl: audioUrl ?? this.audioUrl,
      xpFull: xpFull ?? this.xpFull,
      xpPartial: xpPartial ?? this.xpPartial,
      maxReplays: maxReplays ?? this.maxReplays,
    );
  }
}

/// Full spelling-bee session returned by the backend.
class SpellingBeeGame {
  final String cefrLevel;
  final int timerSeconds;
  final List<SpellingBeeWord> words;

  const SpellingBeeGame({
    required this.cefrLevel,
    required this.timerSeconds,
    required this.words,
  });

  factory SpellingBeeGame.fromJson(Map<String, dynamic> json) {
    return SpellingBeeGame(
      cefrLevel: json['cefr_level'] as String? ?? 'B1',
      timerSeconds: json['timer_seconds'] as int? ?? 90,
      words: (json['words'] as List<dynamic>?)
              ?.map((w) =>
                  SpellingBeeWord.fromJson(w as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'cefr_level': cefrLevel,
        'timer_seconds': timerSeconds,
        'words': words.map((w) => w.toJson()).toList(),
      };

  SpellingBeeGame copyWith({
    String? cefrLevel,
    int? timerSeconds,
    List<SpellingBeeWord>? words,
  }) {
    return SpellingBeeGame(
      cefrLevel: cefrLevel ?? this.cefrLevel,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      words: words ?? this.words,
    );
  }
}

// ── Hangman ───────────────────────────────────────────────────────────────────

/// A simplified hangman word entity — used when only core word data is needed.
class HangmanWord {
  final String wordId;
  final String word;
  final String category;
  final String? hint;
  final String definition;
  final int letterCount;
  final int xpValue;
  final String cefrLevel;

  const HangmanWord({
    required this.wordId,
    required this.word,
    this.category = 'general',
    this.hint,
    this.definition = '',
    required this.letterCount,
    this.xpValue = 10,
    this.cefrLevel = 'A1',
  });

  factory HangmanWord.fromJson(Map<String, dynamic> json) {
    final word = json['word'] as String? ?? '';
    return HangmanWord(
      wordId: json['word_id'] as String? ?? json['id'] as String? ?? '',
      word: word,
      category: json['category'] as String? ?? 'general',
      hint: json['hint'] as String?,
      definition: json['definition'] as String? ?? '',
      letterCount: json['letter_count'] as int? ??
          word.replaceAll(' ', '').length,
      xpValue: json['xp_value'] as int? ?? json['base_xp'] as int? ?? 10,
      cefrLevel: json['cefr_level'] as String? ?? 'A1',
    );
  }

  Map<String, dynamic> toJson() => {
        'word_id': wordId,
        'word': word,
        'category': category,
        if (hint != null) 'hint': hint,
        'definition': definition,
        'letter_count': letterCount,
        'xp_value': xpValue,
        'cefr_level': cefrLevel,
      };

  HangmanWord copyWith({
    String? wordId,
    String? word,
    String? category,
    String? hint,
    String? definition,
    int? letterCount,
    int? xpValue,
    String? cefrLevel,
  }) {
    return HangmanWord(
      wordId: wordId ?? this.wordId,
      word: word ?? this.word,
      category: category ?? this.category,
      hint: hint ?? this.hint,
      definition: definition ?? this.definition,
      letterCount: letterCount ?? this.letterCount,
      xpValue: xpValue ?? this.xpValue,
      cefrLevel: cefrLevel ?? this.cefrLevel,
    );
  }
}

/// Tiered hints for the full hangman game session.
class HangmanHints {
  final String hint1Free;
  final int hint2XpCost;
  final String hint2Definition;
  final int hint3XpCost;

  const HangmanHints({
    required this.hint1Free,
    required this.hint2XpCost,
    required this.hint2Definition,
    required this.hint3XpCost,
  });

  factory HangmanHints.fromJson(Map<String, dynamic> json) {
    return HangmanHints(
      hint1Free: json['hint1_free'] as String? ?? '',
      hint2XpCost: json['hint2_xp_cost'] as int? ?? 5,
      hint2Definition: json['hint2_definition'] as String? ?? '',
      hint3XpCost: json['hint3_xp_cost'] as int? ?? 5,
    );
  }

  Map<String, dynamic> toJson() => {
        'hint1_free': hint1Free,
        'hint2_xp_cost': hint2XpCost,
        'hint2_definition': hint2Definition,
        'hint3_xp_cost': hint3XpCost,
      };

  HangmanHints copyWith({
    String? hint1Free,
    int? hint2XpCost,
    String? hint2Definition,
    int? hint3XpCost,
  }) {
    return HangmanHints(
      hint1Free: hint1Free ?? this.hint1Free,
      hint2XpCost: hint2XpCost ?? this.hint2XpCost,
      hint2Definition: hint2Definition ?? this.hint2Definition,
      hint3XpCost: hint3XpCost ?? this.hint3XpCost,
    );
  }
}

/// Full hangman game session with tiered hints and config.
class HangmanGame {
  final String wordId;
  final String word;
  final int letterCount;
  final String category;
  final String cefrLevel;
  final HangmanHints hints;
  final int maxLives;
  final int baseXp;
  final List<String> availableCategories;

  const HangmanGame({
    required this.wordId,
    required this.word,
    required this.letterCount,
    required this.category,
    required this.cefrLevel,
    required this.hints,
    required this.maxLives,
    required this.baseXp,
    this.availableCategories = const [],
  });

  factory HangmanGame.fromJson(Map<String, dynamic> json) {
    return HangmanGame(
      wordId: json['word_id'] as String? ?? '',
      word: json['word'] as String? ?? '',
      letterCount: json['letter_count'] as int? ?? 0,
      category: json['category'] as String? ?? '',
      cefrLevel: json['cefr_level'] as String? ?? 'A2',
      hints: HangmanHints.fromJson(
          json['hints'] as Map<String, dynamic>? ?? {}),
      maxLives: json['max_lives'] as int? ?? 6,
      baseXp: json['base_xp'] as int? ?? 10,
      availableCategories:
          (json['available_categories'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'word_id': wordId,
        'word': word,
        'letter_count': letterCount,
        'category': category,
        'cefr_level': cefrLevel,
        'hints': hints.toJson(),
        'max_lives': maxLives,
        'base_xp': baseXp,
        'available_categories': availableCategories,
      };

  HangmanGame copyWith({
    String? wordId,
    String? word,
    int? letterCount,
    String? category,
    String? cefrLevel,
    HangmanHints? hints,
    int? maxLives,
    int? baseXp,
    List<String>? availableCategories,
  }) {
    return HangmanGame(
      wordId: wordId ?? this.wordId,
      word: word ?? this.word,
      letterCount: letterCount ?? this.letterCount,
      category: category ?? this.category,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      hints: hints ?? this.hints,
      maxLives: maxLives ?? this.maxLives,
      baseXp: baseXp ?? this.baseXp,
      availableCategories: availableCategories ?? this.availableCategories,
    );
  }
}

// ── Fill in the Blank ─────────────────────────────────────────────────────────

/// A fill-in-the-blank question.
///
/// [sentence] contains '___' as the blank placeholder.
/// [options] contains 4 choices; [correctAnswer] is the right one.
/// Field aliases: id (String), sentence|question, correct_answer.
class FillBlankQuestion {
  final String id;
  final String sentence;
  final List<String> options;
  final String correctAnswer;
  final String grammarTip;
  final String cefrLevel;
  final String explanation;

  const FillBlankQuestion({
    required this.id,
    required this.sentence,
    required this.options,
    required this.correctAnswer,
    this.grammarTip = '',
    this.cefrLevel = 'A1',
    this.explanation = '',
  });

  factory FillBlankQuestion.fromJson(Map<String, dynamic> json) {
    return FillBlankQuestion(
      id: (json['id'] ?? '').toString(),
      // Accept 'sentence' (new API) or 'question' (legacy).
      sentence:
          json['sentence'] as String? ?? json['question'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((o) => o as String)
              .toList() ??
          [],
      // Accept 'correct_answer' (new API) or derive from 'correct_index' (legacy).
      correctAnswer: json['correct_answer'] as String? ?? (() {
            final idx = json['correct_index'] as int? ?? 0;
            final opts = (json['options'] as List<dynamic>?)
                ?.map((o) => o as String)
                .toList() ??
                const [];
            return (idx >= 0 && idx < opts.length) ? opts[idx] : '';
          }()),
      grammarTip: json['grammar_tip'] as String? ?? '',
      cefrLevel: json['cefr_level'] as String? ?? 'A1',
      explanation: json['explanation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sentence': sentence,
        'options': options,
        'correct_answer': correctAnswer,
        'grammar_tip': grammarTip,
        'cefr_level': cefrLevel,
        'explanation': explanation,
      };

  FillBlankQuestion copyWith({
    String? id,
    String? sentence,
    List<String>? options,
    String? correctAnswer,
    String? grammarTip,
    String? cefrLevel,
    String? explanation,
  }) {
    return FillBlankQuestion(
      id: id ?? this.id,
      sentence: sentence ?? this.sentence,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      grammarTip: grammarTip ?? this.grammarTip,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      explanation: explanation ?? this.explanation,
    );
  }
}

/// Full fill-in-the-blank game session returned by the backend.
class FillBlankGame {
  final String cefrLevel;
  final int timerSecondsPerQuestion;
  final int totalXp;
  final List<FillBlankQuestion> questions;

  const FillBlankGame({
    required this.cefrLevel,
    required this.timerSecondsPerQuestion,
    required this.totalXp,
    required this.questions,
  });

  factory FillBlankGame.fromJson(Map<String, dynamic> json) {
    return FillBlankGame(
      cefrLevel: json['cefr_level'] as String? ?? 'B1',
      timerSecondsPerQuestion:
          json['timer_seconds_per_question'] as int? ?? 15,
      totalXp: json['total_xp'] as int? ?? 25,
      questions: (json['questions'] as List<dynamic>?)
              ?.map((q) =>
                  FillBlankQuestion.fromJson(q as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'cefr_level': cefrLevel,
        'timer_seconds_per_question': timerSecondsPerQuestion,
        'total_xp': totalXp,
        'questions': questions.map((q) => q.toJson()).toList(),
      };

  FillBlankGame copyWith({
    String? cefrLevel,
    int? timerSecondsPerQuestion,
    int? totalXp,
    List<FillBlankQuestion>? questions,
  }) {
    return FillBlankGame(
      cefrLevel: cefrLevel ?? this.cefrLevel,
      timerSecondsPerQuestion:
          timerSecondsPerQuestion ?? this.timerSecondsPerQuestion,
      totalXp: totalXp ?? this.totalXp,
      questions: questions ?? this.questions,
    );
  }
}

// ── Grammar Quiz ──────────────────────────────────────────────────────────────

/// A multiple-choice grammar quiz question — API-aligned entity.
///
/// Uses String [id] and String [correctAnswer] (index-free).
/// See also [GrammarQuestion] for the legacy index-based variant.
class GrammarQuizQuestion {
  final String id;
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String explanation;
  final String topic;
  final String cefrLevel;

  const GrammarQuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctAnswer,
    this.explanation = '',
    this.topic = '',
    this.cefrLevel = 'A1',
  });

  factory GrammarQuizQuestion.fromJson(Map<String, dynamic> json) {
    return GrammarQuizQuestion(
      id: (json['id'] ?? '').toString(),
      question: json['question'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((o) => o as String)
              .toList() ??
          [],
      correctAnswer: json['correct_answer'] as String? ?? (() {
            final idx = json['correct_index'] as int? ?? 0;
            final opts = (json['options'] as List<dynamic>?)
                ?.map((o) => o as String)
                .toList() ??
                const [];
            return (idx >= 0 && idx < opts.length) ? opts[idx] : '';
          }()),
      explanation: json['explanation'] as String? ?? '',
      topic: json['topic'] as String? ?? '',
      cefrLevel: json['cefr_level'] as String? ?? 'A1',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'options': options,
        'correct_answer': correctAnswer,
        'explanation': explanation,
        'topic': topic,
        'cefr_level': cefrLevel,
      };

  GrammarQuizQuestion copyWith({
    String? id,
    String? question,
    List<String>? options,
    String? correctAnswer,
    String? explanation,
    String? topic,
    String? cefrLevel,
  }) {
    return GrammarQuizQuestion(
      id: id ?? this.id,
      question: question ?? this.question,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      explanation: explanation ?? this.explanation,
      topic: topic ?? this.topic,
      cefrLevel: cefrLevel ?? this.cefrLevel,
    );
  }
}

/// Legacy index-based grammar question (used by GrammarQuizGame container).
class GrammarQuestion {
  final int id;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String grammarTip;

  const GrammarQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctIndex,
    this.explanation = '',
    this.grammarTip = '',
  });

  factory GrammarQuestion.fromJson(Map<String, dynamic> json) {
    return GrammarQuestion(
      id: json['id'] as int? ?? 0,
      question: json['question'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      correctIndex: json['correct_index'] as int? ?? 0,
      explanation: json['explanation'] as String? ?? '',
      grammarTip: json['grammar_tip'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'options': options,
        'correct_index': correctIndex,
        'explanation': explanation,
        'grammar_tip': grammarTip,
      };

  GrammarQuestion copyWith({
    int? id,
    String? question,
    List<String>? options,
    int? correctIndex,
    String? explanation,
    String? grammarTip,
  }) {
    return GrammarQuestion(
      id: id ?? this.id,
      question: question ?? this.question,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
      explanation: explanation ?? this.explanation,
      grammarTip: grammarTip ?? this.grammarTip,
    );
  }
}

/// Full grammar-quiz session returned by the backend.
class GrammarQuizGame {
  final String cefrLevel;
  final String topic;
  final int timerSecondsPerQuestion;
  final int totalXp;
  final List<GrammarQuestion> questions;

  const GrammarQuizGame({
    required this.cefrLevel,
    required this.topic,
    required this.timerSecondsPerQuestion,
    required this.totalXp,
    required this.questions,
  });

  factory GrammarQuizGame.fromJson(Map<String, dynamic> json) {
    return GrammarQuizGame(
      cefrLevel: json['cefr_level'] as String? ?? 'B1',
      topic: json['topic'] as String? ?? 'mixed',
      timerSecondsPerQuestion:
          json['timer_seconds_per_question'] as int? ?? 12,
      totalXp: json['total_xp'] as int? ?? 25,
      questions: (json['questions'] as List<dynamic>?)
              ?.map((q) =>
                  GrammarQuestion.fromJson(q as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'cefr_level': cefrLevel,
        'topic': topic,
        'timer_seconds_per_question': timerSecondsPerQuestion,
        'total_xp': totalXp,
        'questions': questions.map((q) => q.toJson()).toList(),
      };

  GrammarQuizGame copyWith({
    String? cefrLevel,
    String? topic,
    int? timerSecondsPerQuestion,
    int? totalXp,
    List<GrammarQuestion>? questions,
  }) {
    return GrammarQuizGame(
      cefrLevel: cefrLevel ?? this.cefrLevel,
      topic: topic ?? this.topic,
      timerSecondsPerQuestion:
          timerSecondsPerQuestion ?? this.timerSecondsPerQuestion,
      totalXp: totalXp ?? this.totalXp,
      questions: questions ?? this.questions,
    );
  }
}

// ── Game Session / Result ─────────────────────────────────────────────────────

/// Payload sent via POST /xp/award after a game session completes.
class GameSessionResult {
  final String gameType;
  final int score;
  final int totalQuestions;
  final int correctAnswers;
  final int durationSeconds;
  final int baseXp;
  final String cefrLevel;

  const GameSessionResult({
    required this.gameType,
    required this.score,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.durationSeconds,
    required this.baseXp,
    this.cefrLevel = 'A1',
  });

  Map<String, dynamic> toJson() => {
        'game_type': gameType,
        'score': score,
        'total_questions': totalQuestions,
        'correct_answers': correctAnswers,
        'duration_seconds': durationSeconds,
        'base_xp': baseXp,
        'cefr_level': cefrLevel,
      };

  GameSessionResult copyWith({
    String? gameType,
    int? score,
    int? totalQuestions,
    int? correctAnswers,
    int? durationSeconds,
    int? baseXp,
    String? cefrLevel,
  }) {
    return GameSessionResult(
      gameType: gameType ?? this.gameType,
      score: score ?? this.score,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      baseXp: baseXp ?? this.baseXp,
      cefrLevel: cefrLevel ?? this.cefrLevel,
    );
  }
}

/// Local game result with computed accuracy and star rating — used in the UI.
class GameResult {
  final GameType gameType;
  final String cefrLevel;
  final int score;
  final int totalQuestions;
  final int correctAnswers;
  final int xpEarned;
  final int durationSeconds;
  final XPAwardResult? xpResult;

  const GameResult({
    required this.gameType,
    required this.cefrLevel,
    required this.score,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.xpEarned,
    required this.durationSeconds,
    this.xpResult,
  });

  double get accuracy =>
      totalQuestions > 0 ? correctAnswers / totalQuestions * 100 : 0;

  int get stars => accuracy >= 90
      ? 3
      : accuracy >= 60
          ? 2
          : 1;

  GameResult copyWith({
    GameType? gameType,
    String? cefrLevel,
    int? score,
    int? totalQuestions,
    int? correctAnswers,
    int? xpEarned,
    int? durationSeconds,
    XPAwardResult? xpResult,
  }) {
    return GameResult(
      gameType: gameType ?? this.gameType,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      score: score ?? this.score,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      xpEarned: xpEarned ?? this.xpEarned,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      xpResult: xpResult ?? this.xpResult,
    );
  }
}

// ── XP System ─────────────────────────────────────────────────────────────────

/// A single XP transaction entry in the user's XP history.
class XPTransaction {
  final String id;
  final int amount;
  final String source;
  final String? sourceDetail;
  final bool leveledUp;
  final DateTime createdAt;

  const XPTransaction({
    required this.id,
    required this.amount,
    required this.source,
    this.sourceDetail,
    this.leveledUp = false,
    required this.createdAt,
  });

  factory XPTransaction.fromJson(Map<String, dynamic> json) {
    return XPTransaction(
      id: json['id'] as String? ?? '',
      amount: json['amount'] as int? ?? 0,
      source: json['source'] as String? ?? '',
      sourceDetail: json['source_detail'] as String?,
      leveledUp: json['leveled_up'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ??
              DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'source': source,
        if (sourceDetail != null) 'source_detail': sourceDetail,
        'leveled_up': leveledUp,
        'created_at': createdAt.toIso8601String(),
      };

  XPTransaction copyWith({
    String? id,
    int? amount,
    String? source,
    String? sourceDetail,
    bool? leveledUp,
    DateTime? createdAt,
  }) {
    return XPTransaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      source: source ?? this.source,
      sourceDetail: sourceDetail ?? this.sourceDetail,
      leveledUp: leveledUp ?? this.leveledUp,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Full XP profile for a user, from GET /xp/profile.
class XPProfile {
  final String userId;
  final int totalXp;
  final int numericLevel;
  final double levelProgressPercent;
  final int xpForNextLevel;
  final int currentXpInLevel;
  final int dailyXpToday;
  final int dailyCapRemaining;
  final int streakDays;
  final int bestStreak;
  final List<XPTransaction> recentTransactions;

  const XPProfile({
    required this.userId,
    required this.totalXp,
    required this.numericLevel,
    this.levelProgressPercent = 0.0,
    this.xpForNextLevel = 100,
    this.currentXpInLevel = 0,
    this.dailyXpToday = 0,
    this.dailyCapRemaining = 500,
    this.streakDays = 0,
    this.bestStreak = 0,
    this.recentTransactions = const [],
  });

  factory XPProfile.fromJson(Map<String, dynamic> json) {
    return XPProfile(
      userId: json['user_id'] as String? ?? '',
      totalXp: json['total_xp'] as int? ?? 0,
      numericLevel: json['numeric_level'] as int? ?? 1,
      levelProgressPercent:
          (json['level_progress_percent'] as num?)?.toDouble() ?? 0.0,
      xpForNextLevel: json['xp_for_next_level'] as int? ?? 100,
      currentXpInLevel: json['current_xp_in_level'] as int? ?? 0,
      dailyXpToday: json['daily_xp_today'] as int? ?? 0,
      dailyCapRemaining: json['daily_cap_remaining'] as int? ?? 500,
      streakDays: json['streak_days'] as int? ?? 0,
      bestStreak: json['best_streak'] as int? ?? 0,
      recentTransactions:
          (json['recent_transactions'] as List<dynamic>? ?? [])
              .map((t) =>
                  XPTransaction.fromJson(t as Map<String, dynamic>))
              .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'total_xp': totalXp,
        'numeric_level': numericLevel,
        'level_progress_percent': levelProgressPercent,
        'xp_for_next_level': xpForNextLevel,
        'current_xp_in_level': currentXpInLevel,
        'daily_xp_today': dailyXpToday,
        'daily_cap_remaining': dailyCapRemaining,
        'streak_days': streakDays,
        'best_streak': bestStreak,
        'recent_transactions':
            recentTransactions.map((t) => t.toJson()).toList(),
      };

  XPProfile copyWith({
    String? userId,
    int? totalXp,
    int? numericLevel,
    double? levelProgressPercent,
    int? xpForNextLevel,
    int? currentXpInLevel,
    int? dailyXpToday,
    int? dailyCapRemaining,
    int? streakDays,
    int? bestStreak,
    List<XPTransaction>? recentTransactions,
  }) {
    return XPProfile(
      userId: userId ?? this.userId,
      totalXp: totalXp ?? this.totalXp,
      numericLevel: numericLevel ?? this.numericLevel,
      levelProgressPercent: levelProgressPercent ?? this.levelProgressPercent,
      xpForNextLevel: xpForNextLevel ?? this.xpForNextLevel,
      currentXpInLevel: currentXpInLevel ?? this.currentXpInLevel,
      dailyXpToday: dailyXpToday ?? this.dailyXpToday,
      dailyCapRemaining: dailyCapRemaining ?? this.dailyCapRemaining,
      streakDays: streakDays ?? this.streakDays,
      bestStreak: bestStreak ?? this.bestStreak,
      recentTransactions: recentTransactions ?? this.recentTransactions,
    );
  }
}

/// Result returned from POST /xp/award.
class XPAwardResult {
  final int xpAwarded;
  final int baseXp;
  final double multiplier;
  final int newTotalXp;
  final int dailyXpToday;
  final int dailyCapRemaining;
  final bool leveledUp;
  final int oldLevel;
  final int newLevel;
  final double levelProgressPercent;
  final int xpForNextLevel;
  final int streakDays;
  final String message;

  const XPAwardResult({
    required this.xpAwarded,
    required this.baseXp,
    this.multiplier = 1.0,
    required this.newTotalXp,
    this.dailyXpToday = 0,
    this.dailyCapRemaining = 500,
    this.leveledUp = false,
    required this.oldLevel,
    required this.newLevel,
    this.levelProgressPercent = 0.0,
    this.xpForNextLevel = 100,
    this.streakDays = 0,
    this.message = '',
  });

  factory XPAwardResult.fromJson(Map<String, dynamic> json) {
    return XPAwardResult(
      xpAwarded: json['xp_awarded'] as int? ?? 0,
      baseXp: json['base_xp'] as int? ?? 0,
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
      newTotalXp: json['new_total_xp'] as int? ?? 0,
      dailyXpToday: json['daily_xp_today'] as int? ?? 0,
      dailyCapRemaining: json['daily_cap_remaining'] as int? ?? 500,
      leveledUp: json['leveled_up'] as bool? ?? false,
      oldLevel: json['old_level'] as int? ?? 1,
      newLevel: json['new_level'] as int? ?? 1,
      levelProgressPercent:
          (json['level_progress_percent'] as num?)?.toDouble() ?? 0.0,
      xpForNextLevel: json['xp_for_next_level'] as int? ?? 100,
      streakDays: json['streak_days'] as int? ?? 0,
      message: json['message'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'xp_awarded': xpAwarded,
        'base_xp': baseXp,
        'multiplier': multiplier,
        'new_total_xp': newTotalXp,
        'daily_xp_today': dailyXpToday,
        'daily_cap_remaining': dailyCapRemaining,
        'leveled_up': leveledUp,
        'old_level': oldLevel,
        'new_level': newLevel,
        'level_progress_percent': levelProgressPercent,
        'xp_for_next_level': xpForNextLevel,
        'streak_days': streakDays,
        'message': message,
      };

  XPAwardResult copyWith({
    int? xpAwarded,
    int? baseXp,
    double? multiplier,
    int? newTotalXp,
    int? dailyXpToday,
    int? dailyCapRemaining,
    bool? leveledUp,
    int? oldLevel,
    int? newLevel,
    double? levelProgressPercent,
    int? xpForNextLevel,
    int? streakDays,
    String? message,
  }) {
    return XPAwardResult(
      xpAwarded: xpAwarded ?? this.xpAwarded,
      baseXp: baseXp ?? this.baseXp,
      multiplier: multiplier ?? this.multiplier,
      newTotalXp: newTotalXp ?? this.newTotalXp,
      dailyXpToday: dailyXpToday ?? this.dailyXpToday,
      dailyCapRemaining: dailyCapRemaining ?? this.dailyCapRemaining,
      leveledUp: leveledUp ?? this.leveledUp,
      oldLevel: oldLevel ?? this.oldLevel,
      newLevel: newLevel ?? this.newLevel,
      levelProgressPercent: levelProgressPercent ?? this.levelProgressPercent,
      xpForNextLevel: xpForNextLevel ?? this.xpForNextLevel,
      streakDays: streakDays ?? this.streakDays,
      message: message ?? this.message,
    );
  }
}

// ── Daily Challenge ───────────────────────────────────────────────────────────

/// A daily game challenge shown on the hub screen.
class DailyChallenge {
  final String gameType;
  final String description;
  final int targetScore;
  final int bonusMultiplier;
  final bool completed;
  final DateTime resetsAt;

  const DailyChallenge({
    required this.gameType,
    required this.description,
    this.targetScore = 100,
    this.bonusMultiplier = 2,
    this.completed = false,
    required this.resetsAt,
  });

  factory DailyChallenge.fromJson(Map<String, dynamic> json) {
    return DailyChallenge(
      gameType: json['game_type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      targetScore: json['target_score'] as int? ?? 100,
      bonusMultiplier: json['bonus_multiplier'] as int? ?? 2,
      completed: json['completed'] as bool? ?? false,
      resetsAt: json['resets_at'] != null
          ? DateTime.tryParse(json['resets_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'game_type': gameType,
        'description': description,
        'target_score': targetScore,
        'bonus_multiplier': bonusMultiplier,
        'completed': completed,
        'resets_at': resetsAt.toIso8601String(),
      };

  DailyChallenge copyWith({
    String? gameType,
    String? description,
    int? targetScore,
    int? bonusMultiplier,
    bool? completed,
    DateTime? resetsAt,
  }) {
    return DailyChallenge(
      gameType: gameType ?? this.gameType,
      description: description ?? this.description,
      targetScore: targetScore ?? this.targetScore,
      bonusMultiplier: bonusMultiplier ?? this.bonusMultiplier,
      completed: completed ?? this.completed,
      resetsAt: resetsAt ?? this.resetsAt,
    );
  }
}

// ── Leaderboard ───────────────────────────────────────────────────────────────

/// A single entry in the XP leaderboard — includes [isCurrentUser] flag.
class LeaderboardEntry {
  final int rank;
  final String userId;
  final String username;
  final int totalXp;
  final int numericLevel;
  final int weeklyXp;
  final bool isCurrentUser;

  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.username,
    required this.totalXp,
    this.numericLevel = 1,
    this.weeklyXp = 0,
    this.isCurrentUser = false,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: json['rank'] as int? ?? 0,
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      totalXp: json['total_xp'] as int? ?? 0,
      numericLevel: json['numeric_level'] as int? ?? 1,
      weeklyXp: json['weekly_xp'] as int? ?? 0,
      isCurrentUser: json['is_current_user'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'user_id': userId,
        'username': username,
        'total_xp': totalXp,
        'numeric_level': numericLevel,
        'weekly_xp': weeklyXp,
        'is_current_user': isCurrentUser,
      };

  LeaderboardEntry copyWith({
    int? rank,
    String? userId,
    String? username,
    int? totalXp,
    int? numericLevel,
    int? weeklyXp,
    bool? isCurrentUser,
  }) {
    return LeaderboardEntry(
      rank: rank ?? this.rank,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      totalXp: totalXp ?? this.totalXp,
      numericLevel: numericLevel ?? this.numericLevel,
      weeklyXp: weeklyXp ?? this.weeklyXp,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
    );
  }
}

/// Legacy leaderboard user without the [isCurrentUser] flag.
/// Kept for backward compatibility; prefer [LeaderboardEntry] for new code.
class LeaderboardUser {
  final int rank;
  final String userId;
  final String username;
  final int totalXp;
  final int numericLevel;
  final int weeklyXp;

  const LeaderboardUser({
    required this.rank,
    required this.userId,
    required this.username,
    required this.totalXp,
    required this.numericLevel,
    required this.weeklyXp,
  });

  factory LeaderboardUser.fromJson(Map<String, dynamic> json) {
    return LeaderboardUser(
      rank: json['rank'] as int? ?? 0,
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      totalXp: json['total_xp'] as int? ?? 0,
      numericLevel: json['numeric_level'] as int? ?? 1,
      weeklyXp: json['weekly_xp'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'user_id': userId,
        'username': username,
        'total_xp': totalXp,
        'numeric_level': numericLevel,
        'weekly_xp': weeklyXp,
      };

  LeaderboardUser copyWith({
    int? rank,
    String? userId,
    String? username,
    int? totalXp,
    int? numericLevel,
    int? weeklyXp,
  }) {
    return LeaderboardUser(
      rank: rank ?? this.rank,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      totalXp: totalXp ?? this.totalXp,
      numericLevel: numericLevel ?? this.numericLevel,
      weeklyXp: weeklyXp ?? this.weeklyXp,
    );
  }
}
