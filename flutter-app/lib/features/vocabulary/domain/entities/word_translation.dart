/// Localized gloss and definition from a vocabulary item's `translation` map.
/// Both return null when absent or when they only repeat the English text.
String? localizedGloss(
  Map<String, dynamic>? translation,
  String definition,
  String localeCode,
) {
  final text =
      translation?[localeCode] as String? ?? translation?['en'] as String?;
  return _unlessEnglishCopy(text, definition);
}

String? localizedDefinition(
  Map<String, dynamic>? translation,
  String definition,
  String localeCode,
) {
  final defs = translation?['definitions'];
  return _unlessEnglishCopy(defs is Map ? defs[localeCode] : null, definition);
}

List<String> translationExamples(Map<String, dynamic>? translation) {
  final examples = translation?['examples'];
  return examples is List ? examples.whereType<String>().toList() : const [];
}

String? _unlessEnglishCopy(Object? text, String definition) {
  if (text is! String || text.trim().isEmpty) return null;
  if (text.trim().toLowerCase() == definition.trim().toLowerCase()) return null;
  return text;
}
