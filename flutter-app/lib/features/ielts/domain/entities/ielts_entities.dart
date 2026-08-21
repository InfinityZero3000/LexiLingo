// IELTS mock-test entities.
//
// The paper a learner receives never contains the answer key — the backend
// strips it — so nothing here parses `accepted_answers`. Correct answers only
// appear in the result payload, after submission.

enum IeltsSkill { listening, reading, writing, speaking }

IeltsSkill? ieltsSkillFromName(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'listening':
      return IeltsSkill.listening;
    case 'reading':
      return IeltsSkill.reading;
    case 'writing':
      return IeltsSkill.writing;
    case 'speaking':
      return IeltsSkill.speaking;
  }
  return null;
}

String ieltsSkillLabel(IeltsSkill skill) {
  switch (skill) {
    case IeltsSkill.listening:
      return 'Listening';
    case IeltsSkill.reading:
      return 'Reading';
    case IeltsSkill.writing:
      return 'Writing';
    case IeltsSkill.speaking:
      return 'Speaking';
  }
}

class IeltsTestSummary {
  final String id;
  final String title;
  final String? description;
  final String testType;
  final String skillScope;
  final String? targetBand;
  final int sectionCount;
  final int questionCount;
  final int durationMinutes;

  const IeltsTestSummary({
    required this.id,
    required this.title,
    this.description,
    required this.testType,
    required this.skillScope,
    this.targetBand,
    this.sectionCount = 0,
    this.questionCount = 0,
    this.durationMinutes = 0,
  });

  bool get isAcademic => testType == 'academic';

  factory IeltsTestSummary.fromJson(Map<String, dynamic> json) {
    return IeltsTestSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled',
      description: json['description']?.toString(),
      testType: json['test_type']?.toString() ?? 'academic',
      skillScope: json['skill_scope']?.toString() ?? 'full',
      targetBand: json['target_band']?.toString(),
      sectionCount: (json['section_count'] as num?)?.toInt() ?? 0,
      questionCount: (json['question_count'] as num?)?.toInt() ?? 0,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
    );
  }
}

class IeltsQuestion {
  final String key;
  final int? number;
  final String prompt;
  final List<String> options;

  const IeltsQuestion({
    required this.key,
    this.number,
    required this.prompt,
    this.options = const [],
  });

  factory IeltsQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    return IeltsQuestion(
      key: json['key']?.toString() ?? '',
      number: (json['number'] as num?)?.toInt(),
      prompt: json['prompt']?.toString() ?? '',
      options: rawOptions is List
          ? rawOptions.map((o) => o.toString()).toList()
          : const [],
    );
  }
}

class IeltsQuestionGroup {
  final String questionType;
  final String? instructions;
  final List<IeltsQuestion> questions;

  const IeltsQuestionGroup({
    required this.questionType,
    this.instructions,
    this.questions = const [],
  });

  factory IeltsQuestionGroup.fromJson(Map<String, dynamic> json) {
    final raw = json['questions'];
    return IeltsQuestionGroup(
      questionType: json['question_type']?.toString() ?? 'short_answer',
      instructions: json['instructions']?.toString(),
      questions: raw is List
          ? raw
                .whereType<Map>()
                .map((q) => IeltsQuestion.fromJson(Map<String, dynamic>.from(q)))
                .where((q) => q.key.isNotEmpty)
                .toList()
          : const [],
    );
  }
}

class IeltsPart {
  final int order;
  final String? title;
  final String? audioUrl;
  final String? instructions;
  final String? passageTitle;
  final String? passageText;
  final String? partKey;
  final String? prompt;
  final String? cueCard;
  final String? imageUrl;
  final int? minWords;
  final int? suggestedMinutes;
  final int? prepSeconds;
  final int? speakSeconds;
  final List<IeltsQuestionGroup> groups;

  const IeltsPart({
    this.order = 0,
    this.title,
    this.audioUrl,
    this.instructions,
    this.passageTitle,
    this.passageText,
    this.partKey,
    this.prompt,
    this.cueCard,
    this.imageUrl,
    this.minWords,
    this.suggestedMinutes,
    this.prepSeconds,
    this.speakSeconds,
    this.groups = const [],
  });

  factory IeltsPart.fromJson(Map<String, dynamic> json) {
    final raw = json['question_groups'];
    return IeltsPart(
      order: (json['order'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString(),
      audioUrl: json['audio_url']?.toString(),
      instructions: json['instructions']?.toString(),
      passageTitle: json['passage_title']?.toString(),
      passageText: json['passage_text']?.toString(),
      partKey: json['part_key']?.toString(),
      prompt: json['prompt']?.toString(),
      cueCard: json['cue_card']?.toString(),
      imageUrl: json['image_url']?.toString(),
      minWords: (json['min_words'] as num?)?.toInt(),
      suggestedMinutes: (json['suggested_minutes'] as num?)?.toInt(),
      prepSeconds: (json['prep_seconds'] as num?)?.toInt(),
      speakSeconds: (json['speak_seconds'] as num?)?.toInt(),
      groups: raw is List
          ? raw
                .whereType<Map>()
                .map((g) => IeltsQuestionGroup.fromJson(Map<String, dynamic>.from(g)))
                .toList()
          : const [],
    );
  }

  List<IeltsQuestion> get allQuestions =>
      groups.expand((group) => group.questions).toList();
}

class IeltsSection {
  final IeltsSkill skill;
  final int durationMinutes;
  final List<IeltsPart> parts;

  const IeltsSection({
    required this.skill,
    this.durationMinutes = 0,
    this.parts = const [],
  });

  static IeltsSection? fromJson(Map<String, dynamic> json) {
    final skill = ieltsSkillFromName(json['skill']?.toString());
    if (skill == null) return null;
    final raw = json['parts'];
    return IeltsSection(
      skill: skill,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
      parts: raw is List
          ? raw
                .whereType<Map>()
                .map((p) => IeltsPart.fromJson(Map<String, dynamic>.from(p)))
                .toList()
          : const [],
    );
  }

  int get questionCount =>
      parts.fold(0, (sum, part) => sum + part.allQuestions.length);
}

class IeltsPaper {
  final List<IeltsSection> sections;

  const IeltsPaper({this.sections = const []});

  factory IeltsPaper.fromJson(Map<String, dynamic>? json) {
    final raw = json?['sections'];
    if (raw is! List) return const IeltsPaper();
    return IeltsPaper(
      sections: raw
          .whereType<Map>()
          .map((s) => IeltsSection.fromJson(Map<String, dynamic>.from(s)))
          .whereType<IeltsSection>()
          .toList(),
    );
  }

  IeltsSection? sectionFor(IeltsSkill skill) {
    for (final section in sections) {
      if (section.skill == skill) return section;
    }
    return null;
  }
}

class IeltsAttemptState {
  final String attemptId;
  final String status;
  final String skillScope;
  final Map<String, dynamic> answers;
  final IeltsPaper paper;

  const IeltsAttemptState({
    required this.attemptId,
    required this.status,
    required this.skillScope,
    this.answers = const {},
    this.paper = const IeltsPaper(),
  });

  factory IeltsAttemptState.fromJson(Map<String, dynamic> json) {
    final rawAnswers = json['answers'];
    return IeltsAttemptState(
      attemptId: json['attempt_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'in_progress',
      skillScope: json['skill_scope']?.toString() ?? 'full',
      answers: rawAnswers is Map
          ? Map<String, dynamic>.from(rawAnswers)
          : const {},
      paper: IeltsPaper.fromJson(
        json['content'] is Map ? Map<String, dynamic>.from(json['content']) : null,
      ),
    );
  }
}

class IeltsReviewItem {
  final String key;
  final int? number;
  final String prompt;
  final String? userAnswer;
  final String? correctAnswer;
  final bool isCorrect;

  const IeltsReviewItem({
    required this.key,
    this.number,
    required this.prompt,
    this.userAnswer,
    this.correctAnswer,
    required this.isCorrect,
  });

  factory IeltsReviewItem.fromJson(Map<String, dynamic> json) {
    final correct = json['correct_answer'];
    return IeltsReviewItem(
      key: json['key']?.toString() ?? '',
      number: (json['number'] as num?)?.toInt(),
      prompt: json['prompt']?.toString() ?? '',
      userAnswer: json['user_answer']?.toString(),
      correctAnswer: correct is List
          ? correct.map((c) => c.toString()).join(' / ')
          : correct?.toString(),
      isCorrect: json['is_correct'] == true,
    );
  }
}

class IeltsGradingResult {
  final String skill;
  final String partKey;
  final String status;
  final double? band;
  final Map<String, double> criteria;
  final String? reasoning;
  final List<String> strengths;
  final List<String> improvements;
  final List<Map<String, String>> corrections;
  final int wordCount;
  final String? submissionText;

  const IeltsGradingResult({
    required this.skill,
    required this.partKey,
    required this.status,
    this.band,
    this.criteria = const {},
    this.reasoning,
    this.strengths = const [],
    this.improvements = const [],
    this.corrections = const [],
    this.wordCount = 0,
    this.submissionText,
  });

  bool get isPending => status == 'pending';

  factory IeltsGradingResult.fromJson(Map<String, dynamic> json) {
    final rawCriteria = json['criteria'];
    final feedback = json['feedback'] is Map
        ? Map<String, dynamic>.from(json['feedback'])
        : const <String, dynamic>{};
    List<String> stringList(dynamic value) => value is List
        ? value.map((v) => v.toString()).toList()
        : const <String>[];

    return IeltsGradingResult(
      skill: json['skill']?.toString() ?? '',
      partKey: json['part_key']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      band: (json['band'] as num?)?.toDouble(),
      criteria: rawCriteria is Map
          ? rawCriteria.map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0),
            )
          : const {},
      reasoning: feedback['reasoning']?.toString(),
      strengths: stringList(feedback['strengths']),
      improvements: stringList(feedback['improvements']),
      corrections: feedback['corrections'] is List
          ? (feedback['corrections'] as List)
                .whereType<Map>()
                .map(
                  (c) => {
                    'original': c['original']?.toString() ?? '',
                    'corrected': c['corrected']?.toString() ?? '',
                    'note': c['note']?.toString() ?? '',
                  },
                )
                .toList()
          : const [],
      wordCount: (json['word_count'] as num?)?.toInt() ?? 0,
      submissionText: json['submission_text']?.toString(),
    );
  }
}

class IeltsResult {
  final String attemptId;
  final String? testTitle;
  final String status;
  final double? overallBand;
  final Map<String, double?> bands;
  final Map<String, Map<String, int>> rawScores;
  final Map<String, List<IeltsReviewItem>> review;
  final List<IeltsGradingResult> gradings;
  final int timeSpentSeconds;

  const IeltsResult({
    required this.attemptId,
    this.testTitle,
    required this.status,
    this.overallBand,
    this.bands = const {},
    this.rawScores = const {},
    this.review = const {},
    this.gradings = const [],
    this.timeSpentSeconds = 0,
  });

  bool get isAwaitingGrading => gradings.any((g) => g.isPending);

  factory IeltsResult.fromJson(Map<String, dynamic> json) {
    final rawBands = json['bands'];
    final rawScores = json['raw_scores'];
    final rawReview = json['review'];
    final rawGradings = json['gradings'];

    return IeltsResult(
      attemptId: json['attempt_id']?.toString() ?? '',
      testTitle: json['test_title']?.toString(),
      status: json['status']?.toString() ?? 'submitted',
      overallBand: (json['overall_band'] as num?)?.toDouble(),
      timeSpentSeconds: (json['time_spent_seconds'] as num?)?.toInt() ?? 0,
      bands: rawBands is Map
          ? rawBands.map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble()),
            )
          : const {},
      rawScores: rawScores is Map
          ? rawScores.map(
              (k, v) => MapEntry(
                k.toString(),
                v is Map
                    ? v.map(
                        (kk, vv) =>
                            MapEntry(kk.toString(), (vv as num?)?.toInt() ?? 0),
                      )
                    : <String, int>{},
              ),
            )
          : const {},
      review: rawReview is Map
          ? rawReview.map(
              (k, v) => MapEntry(
                k.toString(),
                v is List
                    ? v
                          .whereType<Map>()
                          .map(
                            (item) => IeltsReviewItem.fromJson(
                              Map<String, dynamic>.from(item),
                            ),
                          )
                          .toList()
                    : <IeltsReviewItem>[],
              ),
            )
          : const {},
      gradings: rawGradings is List
          ? rawGradings
                .whereType<Map>()
                .map(
                  (g) =>
                      IeltsGradingResult.fromJson(Map<String, dynamic>.from(g)),
                )
                .toList()
          : const [],
    );
  }
}
