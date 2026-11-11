import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/lexi_followups.dart';

LexiMessage _lexi(
  String content, {
  List<LexiCorrection> corrections = const [],
}) => LexiMessage(
  id: 'm',
  role: 'assistant',
  content: content,
  timestamp: DateTime(2026),
  corrections: corrections,
);

void main() {
  test('endsWithQuestion handles ASCII and full-width marks', () {
    expect(endsWithQuestion('Where do you live? 🦜'), isTrue);
    expect(endsWithQuestion('どこに住んでいますか？'), isTrue);
    expect(endsWithQuestion('Nice work!'), isFalse);
  });

  test('a vocab card offers practice with the word first', () {
    final f = lexiFollowups(
      _lexi('Try this:\n```vocab\nword: achieve\n```'),
      nativeLanguage: 'vi',
    );
    expect(f.take(2), [LexiFollowup.useInSentence, LexiFollowup.quizMe]);
  });

  test('corrections put "explain my mistake" first', () {
    final f = lexiFollowups(
      _lexi(
        'Good try.',
        corrections: const [
          LexiCorrection(
            errorSpan: 'a',
            correction: 'b',
            errorType: 'grammar',
            explanation: 'c',
          ),
        ],
      ),
      nativeLanguage: 'vi',
    );
    expect(f.first, LexiFollowup.explainMistake);
  });

  test('translate is dropped for English speakers; capped; no repeats', () {
    final f = lexiFollowups(_lexi('Hello there.'), nativeLanguage: 'en');
    expect(f, isNot(contains(LexiFollowup.translate)));
    expect(f.length, lessThanOrEqualTo(4));
    expect(f.toSet().length, f.length);
  });

  test('a question does not get "keep going"', () {
    final f = lexiFollowups(
      _lexi('What did you do today?'),
      nativeLanguage: 'vi',
    );
    expect(f, isNot(contains(LexiFollowup.keepGoing)));
  });

  test('prompts sent to Lexi are English; every locale has a label', () {
    for (final f in LexiFollowup.values) {
      expect(f.prompt, matches(RegExp(r'^[\x20-\x7E]+$')), reason: f.name);
    }
    for (final loc in ['en', 'vi', 'es', 'fr', 'ja', 'ko', 'zh']) {
      final json =
          jsonDecode(File('assets/i18n/$loc.json').readAsStringSync())
              as Map<String, dynamic>;
      final lexi = json['lexiChat'] as Map<String, dynamic>;
      for (final f in LexiFollowup.values) {
        final key = f.i18nKey.split('.').last;
        expect((lexi[key] as String?)?.trim(), isNotEmpty, reason: '$loc/$key');
      }
    }
  });
}
