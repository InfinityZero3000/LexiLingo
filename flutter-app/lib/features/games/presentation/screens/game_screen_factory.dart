import 'package:flutter/widgets.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/screens/fill_blank_screen.dart';
import 'package:lexilingo_app/features/games/presentation/screens/grammar_quiz_screen.dart';
import 'package:lexilingo_app/features/games/presentation/screens/hangman_screen.dart';
import 'package:lexilingo_app/features/games/presentation/screens/matching_game_screen.dart';
import 'package:lexilingo_app/features/games/presentation/screens/spelling_bee_screen.dart';
import 'package:lexilingo_app/features/games/presentation/screens/word_scramble_screen.dart';

Widget gameScreenFor(GameType gameType) => switch (gameType) {
  GameType.wordScramble => const WordScrambleScreen(),
  GameType.fillBlank => const FillBlankScreen(),
  GameType.matching => const MatchingGameScreen(),
  GameType.spellingBee => const SpellingBeeScreen(),
  GameType.grammarQuiz => const GrammarQuizScreen(),
  GameType.hangman => const HangmanScreen(),
};
