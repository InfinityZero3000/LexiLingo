import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';

class QuestionItem {
  final String id, prompt, questionType, difficultyLevel;
  final List<dynamic> options;
  final dynamic answer;
  final String? explanation, grammarId;
  final List<String> tags;
  final bool isActive;

  const QuestionItem({required this.id, required this.prompt, required this.questionType,
    required this.difficultyLevel, required this.options, this.answer, this.explanation,
    this.grammarId, required this.tags, required this.isActive});

  factory QuestionItem.fromJson(Map<String, dynamic> json) => QuestionItem(
    id: json['id']?.toString() ?? '', prompt: json['prompt'] ?? '',
    questionType: json['question_type'] ?? 'mcq',
    difficultyLevel: json['difficulty_level'] ?? 'A1',
    options: List<dynamic>.from(json['options'] as List? ?? const []), answer: json['answer'],
    explanation: json['explanation']?.toString(), grammarId: json['grammar_id']?.toString(),
    tags: (json['tags'] as List? ?? const []).map((e) => e.toString()).toList(),
    isActive: json['is_active'] != false,
  );
}

class TestExam {
  final String id, title, level;
  final String? description;
  final int durationMinutes, passingScore;
  final List<String> questionIds;
  final bool isPublished;

  const TestExam({required this.id, required this.title, this.description, required this.level,
    required this.durationMinutes, required this.passingScore, required this.questionIds,
    required this.isPublished});

  factory TestExam.fromJson(Map<String, dynamic> json) => TestExam(
    id: json['id']?.toString() ?? '', title: json['title'] ?? '',
    description: json['description']?.toString(), level: json['level'] ?? 'A1',
    durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 20,
    passingScore: (json['passing_score'] as num?)?.toInt() ?? 70,
    questionIds: (json['question_ids'] as List? ?? const []).map((e) => e.toString()).toList(),
    isPublished: json['is_published'] == true,
  );
}

class ContentLabRepository {
  final _api = ApiClient.instance;

  Future<List<QuestionItem>> listQuestions() async {
    final response = await _api.get(ApiEndpoints.adminQuestions, params: {'limit': 100, 'offset': 0});
    return ((response['data'] as List?) ?? const [])
        .map((e) => QuestionItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createQuestion(Map<String, dynamic> data) =>
      _api.post(ApiEndpoints.adminQuestions, data: data);
  Future<void> updateQuestion(String id, Map<String, dynamic> data) =>
      _api.put('${ApiEndpoints.adminQuestions}/$id', data: data);
  Future<void> deleteQuestion(String id) => _api.delete('${ApiEndpoints.adminQuestions}/$id');

  Future<List<TestExam>> listTestExams() async {
    final response = await _api.get(ApiEndpoints.adminTestExams, params: {'limit': 100, 'offset': 0});
    return ((response['data'] as List?) ?? const [])
        .map((e) => TestExam.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createTestExam(Map<String, dynamic> data) =>
      _api.post(ApiEndpoints.adminTestExams, data: data);
  Future<void> updateTestExam(String id, Map<String, dynamic> data) =>
      _api.put('${ApiEndpoints.adminTestExams}/$id', data: data);
  Future<void> deleteTestExam(String id) => _api.delete('${ApiEndpoints.adminTestExams}/$id');
}
