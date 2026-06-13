class SpeakingAnswerMatch {
  final String normalizedTranscript;
  final String normalizedTarget;
  final double similarity;
  final bool isApproved;

  const SpeakingAnswerMatch({
    required this.normalizedTranscript,
    required this.normalizedTarget,
    required this.similarity,
    required this.isApproved,
  });
}

class SpeakingAnswerMatcher {
  static const double defaultApprovalThreshold = 0.85;

  const SpeakingAnswerMatcher._();

  static SpeakingAnswerMatch evaluate({
    required String transcript,
    required String target,
    double approvalThreshold = defaultApprovalThreshold,
  }) {
    final normalizedTranscript = normalize(transcript);
    final normalizedTarget = normalize(target);
    final similarity = calculateSimilarity(
      normalizedTranscript,
      normalizedTarget,
    );

    return SpeakingAnswerMatch(
      normalizedTranscript: normalizedTranscript,
      normalizedTarget: normalizedTarget,
      similarity: similarity,
      isApproved:
          normalizedTranscript.isNotEmpty &&
          normalizedTarget.isNotEmpty &&
          similarity >= approvalThreshold,
    );
  }

  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
        .replaceAll(RegExp(r"\s+"), ' ')
        .trim();
  }

  static double calculateSimilarity(String first, String second) {
    if (first == second) return first.isEmpty ? 0 : 1;
    if (first.isEmpty || second.isEmpty) return 0;

    final longestLength = first.length > second.length
        ? first.length
        : second.length;
    final distance = _editDistance(first, second);
    return ((longestLength - distance) / longestLength).clamp(0, 1);
  }

  static int _editDistance(String first, String second) {
    var previous = List<int>.generate(second.length + 1, (index) => index);

    for (var firstIndex = 0; firstIndex < first.length; firstIndex++) {
      final current = List<int>.filled(second.length + 1, 0);
      current[0] = firstIndex + 1;

      for (var secondIndex = 0; secondIndex < second.length; secondIndex++) {
        final substitutionCost = first[firstIndex] == second[secondIndex]
            ? 0
            : 1;
        current[secondIndex + 1] = _minimum(
          current[secondIndex] + 1,
          previous[secondIndex + 1] + 1,
          previous[secondIndex] + substitutionCost,
        );
      }

      previous = current;
    }

    return previous[second.length];
  }

  static int _minimum(int first, int second, int third) {
    var result = first < second ? first : second;
    if (third < result) result = third;
    return result;
  }
}
