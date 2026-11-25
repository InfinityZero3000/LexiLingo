/// Words that are acronyms, not words: shown as the exam or framework writes them.
const _acronyms = {
  'ielts',
  'toefl',
  'toeic',
  'cefr',
  'esl',
  'efl',
  'ai',
  'uk',
  'us',
  'bbc',
};

/// Words a tag joins with a hyphen ("pre_intermediate" is "Pre-Intermediate").
const _hyphenPrefixes = {'pre', 'post', 'non', 'self', 'co'};

/// A course tag as a learner should read it: `ielts` -> IELTS, `cefr_a1` -> CEFR A1,
/// `band_6_5` -> Band 6.5, `pre_intermediate` -> Pre-Intermediate.
///
/// A tag is a slug; capitalising each part alone gave "Ielts", "Band 6 5" and
/// "Pre Intermediate" on the course cards.
String courseTagLabel(String tag) {
  final parts = tag
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .split('_')
      .where((p) => p.isNotEmpty)
      .toList();
  final out = <String>[];
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    final next = i + 1 < parts.length ? parts[i + 1] : null;
    final isDigit = RegExp(r'^\d$').hasMatch(part);
    final afterBand = i > 0 && parts[i - 1] == 'band';
    if (afterBand &&
        isDigit &&
        next != null &&
        RegExp(r'^\d$').hasMatch(next)) {
      // IELTS bands are written 6.5, not "6 5"; only after "band" so a tag
      // like "grade_1_2" is left alone.
      out.add('$part.$next');
      i++;
      continue;
    }
    if (_hyphenPrefixes.contains(part) &&
        next != null &&
        !RegExp(r'^\d+$').hasMatch(next)) {
      out.add('${_cap(part)}-${_cap(next)}');
      i++;
      continue;
    }
    out.add(_acronyms.contains(part) ? part.toUpperCase() : _cap(part));
  }
  return out.join(' ');
}

String _cap(String word) =>
    word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}';
