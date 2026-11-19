/// Error-type codes sent by ai-service (DIAGNOSIS_LABELS) mapped onto i18n keys.
library;

const List<String> kGrammarLabelCodes = [
  'article_missing',
  'article_a_an',
  'article_the',
  'preposition',
  'subject_verb_agreement',
  'verb_tense',
  'verb_form',
  'irregular_verb',
  'missing_auxiliary',
  'missing_be',
  'passive_voice',
  'noun_number',
  'possessive',
  'pronoun_case',
  'pronoun_missing',
  'word_order',
  'word_form',
  'comparison',
  'conjunction',
  'particle',
  'spelling',
  'punctuation',
  'word_choice',
  'other',
];

// Codes older servers and the rule-based diagnosis sent before the closed set.
const Map<String, String> _legacyCodes = {
  'tense_error': 'verb_tense',
  'tense': 'verb_tense',
  'past_tense': 'verb_tense',
  'article_error': 'article_a_an',
  'article': 'article_a_an',
  'preposition_error': 'preposition',
  'plural_error': 'noun_number',
  'plural': 'noun_number',
  'pronoun_error': 'pronoun_case',
  'third_person_s': 'subject_verb_agreement',
  'present_perfect': 'verb_form',
};

const Set<String> _noPractice = {'spelling', 'punctuation'};
const Set<String> _vocabularySkill = {'spelling', 'word_choice'};

String? _resolve(String? code) {
  final normalized = code?.trim().toLowerCase().replaceAll(
    RegExp(r'[\s\-/]+'),
    '_',
  );
  if (normalized == null || normalized.isEmpty) return null;
  final resolved = _legacyCodes[normalized] ?? normalized;
  return kGrammarLabelCodes.contains(resolved) ? resolved : null;
}

/// i18n key for [code], or null when the code is unknown.
String? grammarLabelKey(String? code) {
  final resolved = _resolve(code);
  return resolved == null ? null : 'chat.errorLabel.$resolved';
}

/// Whether to show an error-type pill: known and not the catch-all.
bool grammarLabelIsInformative(String? code) {
  final resolved = _resolve(code);
  return resolved != null && resolved != 'other';
}

/// Spelling and punctuation have no grammar exercise to route to.
bool grammarLabelHasPractice(String? code) =>
    !_noPractice.contains(_resolve(code));

/// The Mistake Notebook skill for a correction; never the error label itself.
String grammarSkillFor(String? code) =>
    _vocabularySkill.contains(_resolve(code)) ? 'vocabulary' : 'grammar';
