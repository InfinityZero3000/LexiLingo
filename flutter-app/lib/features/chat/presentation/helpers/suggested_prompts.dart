/// Prompt chips the learner has not already used in this session.
library;

String _normalize(String text) => text
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceFirst(RegExp(r'[ .!?,;:]+$'), '');

List<String> remainingSuggestedPrompts(
  List<String> prompts,
  Iterable<String> sentUserMessages,
) {
  final sent = sentUserMessages.map(_normalize).toSet();
  return [
    for (final prompt in prompts)
      if (!sent.contains(_normalize(prompt))) prompt,
  ];
}
