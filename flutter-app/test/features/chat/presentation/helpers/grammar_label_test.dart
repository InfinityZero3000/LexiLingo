import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/chat/presentation/helpers/grammar_label.dart';

Map<String, dynamic> _table(String code) =>
    jsonDecode(File('assets/i18n/$code.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('there are exactly the 24 DIAGNOSIS_LABELS codes', () {
    expect(kGrammarLabelCodes, hasLength(24));
    expect(kGrammarLabelCodes.toSet(), hasLength(24));
  });

  for (final code in kGrammarLabelCodes) {
    test('$code maps to a key translated in every locale', () {
      final key = grammarLabelKey(code);
      expect(key, 'chat.errorLabel.$code');
      for (final lang in ['vi', 'en', 'ja', 'ko', 'zh', 'fr', 'es']) {
        final labels = (_table(lang)['chat'] as Map)['errorLabel'] as Map;
        expect(labels[code], isA<String>(), reason: '$lang is missing $code');
        expect((labels[code] as String).trim(), isNotEmpty);
      }
    });
  }

  test('older *_error codes map onto the closed set', () {
    expect(grammarLabelKey('tense_error'), 'chat.errorLabel.verb_tense');
    expect(grammarLabelKey('article_error'), 'chat.errorLabel.article_a_an');
    expect(grammarLabelKey('preposition_error'), 'chat.errorLabel.preposition');
    expect(grammarLabelKey('plural_error'), 'chat.errorLabel.noun_number');
    expect(grammarLabelKey('pronoun_error'), 'chat.errorLabel.pronoun_case');
    expect(
      grammarLabelKey('third_person_s'),
      'chat.errorLabel.subject_verb_agreement',
    );
    expect(grammarLabelKey('word_order'), 'chat.errorLabel.word_order');
  });

  test('codes are normalised; unknown and empty give null', () {
    expect(grammarLabelKey('  Verb-Tense '), 'chat.errorLabel.verb_tense');
    expect(grammarLabelKey('vibes'), isNull);
    expect(grammarLabelKey(''), isNull);
    expect(grammarLabelKey(null), isNull);
  });

  test('only a known, non-other label is shown as a pill', () {
    expect(grammarLabelIsInformative('verb_tense'), isTrue);
    expect(grammarLabelIsInformative('other'), isFalse);
    expect(grammarLabelIsInformative('vibes'), isFalse);
    expect(grammarLabelIsInformative(null), isFalse);
  });

  test('spelling and punctuation have no practice target', () {
    expect(grammarLabelHasPractice('spelling'), isFalse);
    expect(grammarLabelHasPractice('punctuation'), isFalse);
    expect(grammarLabelHasPractice('verb_tense'), isTrue);
    expect(grammarLabelHasPractice(null), isTrue);
  });

  test('skill is grammar or vocabulary, never the label', () {
    expect(grammarSkillFor('spelling'), 'vocabulary');
    expect(grammarSkillFor('word_choice'), 'vocabulary');
    expect(grammarSkillFor('verb_tense'), 'grammar');
    expect(grammarSkillFor('article_error'), 'grammar');
    expect(grammarSkillFor('vibes'), 'grammar');
    expect(grammarSkillFor(null), 'grammar');
  });
}
