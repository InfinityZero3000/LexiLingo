import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';

/// [i18nKey] is what the learner reads (their app language); [prompt] is what
/// Lexi receives — always English, since Lexi only works in English.
enum LexiFollowup {
  explainMistake('lexiChat.followupExplainMistake', 'Explain my mistake'),
  useInSentence(
    'lexiChat.followupUseInSentence',
    'Use that word in a sentence',
  ),
  quizMe('lexiChat.followupQuizMe', 'Quiz me on this'),
  giveExample('lexiChat.followupGiveExample', 'Give me an example'),
  simpler('lexiChat.followupSimpler', 'Explain it more simply'),
  translate(
    'lexiChat.followupTranslate',
    'Translate that into my native language',
  ),
  keepGoing('lexiChat.followupContinue', "Let's keep going");

  const LexiFollowup(this.i18nKey, this.prompt);
  final String i18nKey;
  final String prompt;
}

/// Full-width marks included so ja/zh/ko questions count. Mirrors the server's
/// `ends_with_question` — keep the two in step.
bool endsWithQuestion(String text) {
  final tail = text.length > 80 ? text.substring(text.length - 80) : text;
  return tail.contains('?') || tail.contains('？');
}

/// Chips that fit what Lexi just said, strongest signal first, at most [max].
/// Answers to Lexi's question come from the server, not from here.
List<LexiFollowup> lexiFollowups(
  LexiMessage message, {
  required String nativeLanguage,
  int max = 4,
}) {
  final text = message.content;
  final isQuestion = endsWithQuestion(text);
  final picks = <LexiFollowup>[
    if (message.hasCorrections) LexiFollowup.explainMistake,
    if (text.contains('```vocab')) LexiFollowup.useInSentence,
    if (text.contains('```vocab') || text.contains('```fix'))
      LexiFollowup.quizMe,
    if (text.contains('```steps') || text.contains('|---'))
      LexiFollowup.giveExample,
    LexiFollowup.giveExample,
    LexiFollowup.simpler,
    if (nativeLanguage != 'en') LexiFollowup.translate,
    if (!isQuestion) LexiFollowup.keepGoing,
  ];
  return picks.toSet().take(max).toList();
}
