import '../../../core/network/api_client.dart';

class ContentQaJob {
  final String id;
  final String status;
  final Map<String, dynamic> config;
  final List<String> warnings;
  final List<String> blockingErrors;
  final Map<String, dynamic> createdEntityIds;
  final String? errorMessage;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  const ContentQaJob({
    required this.id,
    required this.status,
    required this.config,
    required this.warnings,
    required this.blockingErrors,
    required this.createdEntityIds,
    this.errorMessage,
    this.updatedAt,
    this.completedAt,
  });

  factory ContentQaJob.fromJson(Map<String, dynamic> json) => ContentQaJob(
        id: json['id']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        config: (json['config'] as Map?)?.cast<String, dynamic>() ?? {},
        warnings: ((json['warnings'] as List?) ?? []).map((e) => e.toString()).toList(),
        blockingErrors: ((json['blocking_errors'] as List?) ?? []).map((e) => e.toString()).toList(),
        createdEntityIds: (json['created_entity_ids'] as Map?)?.cast<String, dynamic>() ?? {},
        errorMessage: json['error_message']?.toString(),
        updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
        completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? ''),
      );

  String get title {
    final focus = config['title_focus']?.toString().trim();
    if (focus?.isNotEmpty == true) return focus!;
    final levels = (config['levels'] as List?)?.join(', ');
    return levels?.isNotEmpty == true ? levels! : 'Content job';
  }
}

class ContentQaExercise {
  final String id;
  final String uiType;
  final String? phase;
  final String question;
  final String correctAnswer;
  final dynamic options;
  final String? explanation;

  const ContentQaExercise({
    required this.id,
    required this.uiType,
    required this.question,
    required this.correctAnswer,
    this.phase,
    this.options,
    this.explanation,
  });

  factory ContentQaExercise.fromJson(Map<String, dynamic> json) => ContentQaExercise(
        id: json['id']?.toString() ?? '',
        uiType: json['ui_type']?.toString() ?? json['type']?.toString() ?? '',
        phase: json['phase']?.toString(),
        question: json['question']?.toString() ?? '',
        correctAnswer: json['correct_answer']?.toString() ?? '',
        options: json['options'],
        explanation: json['explanation']?.toString(),
      );
}

class ContentQaLesson {
  final String title;
  final String? outcome;
  final List<ContentQaExercise> exercises;

  const ContentQaLesson({required this.title, this.outcome, required this.exercises});

  factory ContentQaLesson.fromJson(Map<String, dynamic> json) => ContentQaLesson(
        title: json['title']?.toString() ?? 'Untitled lesson',
        outcome: json['outcome']?.toString(),
        exercises: ((json['exercises'] as List?) ?? [])
            .map((e) => ContentQaExercise.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class ContentQaPreview {
  final List<ContentQaLesson> lessons;
  final int courseCount;
  final int unitCount;
  final int vocabularyCount;
  final List<String> blockingErrors;
  final List<String> warnings;

  const ContentQaPreview({
    required this.lessons,
    required this.courseCount,
    required this.unitCount,
    required this.vocabularyCount,
    required this.blockingErrors,
    required this.warnings,
  });

  factory ContentQaPreview.fromJson(Map<String, dynamic> json) {
    final courses = (json['courses'] as List?) ?? [];
    final lessons = <ContentQaLesson>[];
    var units = 0;
    var vocabulary = 0;
    for (final course in courses) {
      final courseMap = (course as Map).cast<String, dynamic>();
      final courseUnits = (courseMap['units'] as List?) ?? [];
      units += courseUnits.length;
      for (final unit in courseUnits) {
        final unitLessons = (((unit as Map)['lessons'] as List?) ?? []);
        for (final lesson in unitLessons) {
          final lessonMap = (lesson as Map).cast<String, dynamic>();
          vocabulary += ((lessonMap['vocabulary'] as List?) ?? []).length;
          lessons.add(ContentQaLesson.fromJson(lessonMap));
        }
      }
    }
    final quality = (json['quality'] as Map?)?.cast<String, dynamic>() ?? {};
    return ContentQaPreview(
      lessons: lessons,
      courseCount: courses.length,
      unitCount: units,
      vocabularyCount: vocabulary,
      blockingErrors: ((quality['blocking_errors'] as List?) ?? []).map((e) => e.toString()).toList(),
      warnings: ((quality['warnings'] as List?) ?? []).map((e) => e.toString()).toList(),
    );
  }

  int get exerciseCount => lessons.fold(0, (sum, lesson) => sum + lesson.exercises.length);
}

class ContentQaQueue {
  final List<ContentQaJob> reviewable;
  final List<ContentQaJob> failed;
  final List<ContentQaJob> applied;
  final int total;

  const ContentQaQueue({required this.reviewable, required this.failed, required this.applied, required this.total});
}

class ContentQaRepository {
  static const _base = '/admin/content-agent/jobs';
  final _api = ApiClient.instance;

  Map<String, dynamic> _data(Map<String, dynamic> response) =>
      (response['data'] as Map?)?.cast<String, dynamic>() ?? {};

  Future<ContentQaQueue> getQueue() async {
    final data = _data(await _api.get(_base));
    final rawJobs = (data['jobs'] as List?) ?? (data['items'] as List?) ?? [];
    final jobs = rawJobs.map((e) => ContentQaJob.fromJson((e as Map).cast<String, dynamic>())).toList();
    return ContentQaQueue(
      reviewable: jobs.where((job) => job.status == 'preview_ready').toList(),
      failed: jobs.where((job) => job.status == 'failed').toList(),
      applied: jobs.where((job) => job.status == 'completed').toList(),
      total: (data['total'] as num?)?.toInt() ?? jobs.length,
    );
  }

  Future<ContentQaJob> getJob(String jobId) async =>
      ContentQaJob.fromJson(_data(await _api.get('$_base/$jobId')));

  Future<ContentQaPreview> getPreview(String jobId) async {
    final data = _data(await _api.get('$_base/$jobId/preview'));
    final raw = data.containsKey('courses') ? data : (data['artifact'] ?? data['preview']);
    return ContentQaPreview.fromJson((raw as Map).cast<String, dynamic>());
  }

  Future<ContentQaPreview> updateRecord(String jobId, String recordId, Map<String, dynamic> update) async {
    final data = _data(await _api.patch('$_base/$jobId/records/$recordId', data: update));
    return ContentQaPreview.fromJson((data['artifact'] as Map).cast<String, dynamic>());
  }

  Future<void> apply(String jobId) => _api.post('$_base/$jobId/apply');
  Future<void> retry(String jobId) => _api.post('$_base/$jobId/retry');
  Future<void> cancel(String jobId) => _api.post('$_base/$jobId/cancel');
}
