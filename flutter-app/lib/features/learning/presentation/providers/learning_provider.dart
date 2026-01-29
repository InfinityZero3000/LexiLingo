import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_attempt_model.dart';
import 'package:lexilingo_app/features/learning/data/models/answer_response_model.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_complete_model.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/start_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/submit_answer_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/complete_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_course_roadmap_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_lesson_content_usecase.dart';

/// Learning Provider - Manages learning sessions, roadmap, and lesson progress
class LearningProvider with ChangeNotifier {
  final StartLessonUseCase _startLessonUseCase;
  final SubmitAnswerUseCase _submitAnswerUseCase;
  final CompleteLessonUseCase _completeLessonUseCase;
  final GetCourseRoadmapUseCase _getCourseRoadmapUseCase;
  final GetLessonContentUseCase _getLessonContentUseCase;

  LearningProvider({
    required StartLessonUseCase startLessonUseCase,
    required SubmitAnswerUseCase submitAnswerUseCase,
    required CompleteLessonUseCase completeLessonUseCase,
    required GetCourseRoadmapUseCase getCourseRoadmapUseCase,
    required GetLessonContentUseCase getLessonContentUseCase,
  })  : _startLessonUseCase = startLessonUseCase,
        _submitAnswerUseCase = submitAnswerUseCase,
        _completeLessonUseCase = completeLessonUseCase,
        _getCourseRoadmapUseCase = getCourseRoadmapUseCase,
        _getLessonContentUseCase = getLessonContentUseCase;

  // ROADMAP STATE
  CourseRoadmapModel? _courseRoadmap;
  bool _isLoadingRoadmap = false;
  String? _roadmapError;

  CourseRoadmapModel? get courseRoadmap => _courseRoadmap;
  bool get isLoadingRoadmap => _isLoadingRoadmap;
  String? get roadmapError => _roadmapError;

  Future<void> loadRoadmap(String courseId) async {
    _isLoadingRoadmap = true;
    _roadmapError = null;
    notifyListeners();

    final result = await _getCourseRoadmapUseCase(
      GetCourseRoadmapParams(courseId: courseId),
    );

    result.fold(
      (failure) {
        _roadmapError = failure.message;
        _isLoadingRoadmap = false;
      },
      (roadmap) {
        _courseRoadmap = roadmap;
        _isLoadingRoadmap = false;
      },
    );
    notifyListeners();
  }

  // LESSON SESSION STATE
  LessonEntity? _currentLesson;
  LessonAttemptModel? _currentAttempt;
  int _currentExerciseIndex = 0;
  Map<int, String> _userAnswers = {};
  Map<int, bool> _answerResults = {};
  Map<int, AnswerResponseModel> _answerResponses = {};
  bool _isLoading = false;
  String? _error;
  int _xpEarned = 0;
  int _livesRemaining = 3;
  int _hintsRemaining = 3;
  DateTime? _exerciseStartTime;
  LessonCompleteModel? _lessonResult;

  LessonEntity? get currentLesson => _currentLesson;
  LessonAttemptModel? get currentAttempt => _currentAttempt;
  int get currentExerciseIndex => _currentExerciseIndex;
  int get totalExercises => _currentLesson?.exercises.length ?? 0;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get xpEarned => _xpEarned;
  int get livesRemaining => _livesRemaining;
  int get hintsRemaining => _hintsRemaining;
  LessonCompleteModel? get lessonResult => _lessonResult;

  Exercise? get currentExercise {
    if (_currentLesson == null || _currentExerciseIndex >= totalExercises) {
      return null;
    }
    return _currentLesson!.exercises[_currentExerciseIndex];
  }

  bool get isCurrentAnswered => _userAnswers.containsKey(_currentExerciseIndex);
  String? get currentUserAnswer => _userAnswers[_currentExerciseIndex];
  bool? get isCurrentCorrect => _answerResults[_currentExerciseIndex];
  AnswerResponseModel? get currentAnswerResponse => _answerResponses[_currentExerciseIndex];
  bool get isCompleted => _currentLesson != null && _currentExerciseIndex >= totalExercises;
  int get score => _answerResults.values.where((result) => result).length;
  double get progress => totalExercises == 0 ? 0 : (_currentExerciseIndex + 1) / totalExercises;

  Future<void> startLesson(String courseId, String lessonId) async {
    _isLoading = true;
    _error = null;
    _lessonResult = null;
    notifyListeners();

    try {
      final attemptResult = await _startLessonUseCase(StartLessonParams(lessonId: lessonId));
      attemptResult.fold(
        (failure) => debugPrint('Start lesson API failed: ${failure.message}'),
        (attempt) {
          _currentAttempt = attempt;
          _livesRemaining = attempt.livesRemaining;
          _hintsRemaining = attempt.hintsAvailable;
        },
      );

      final contentResult = await _getLessonContentUseCase(GetLessonContentParams(lessonId: lessonId));
      contentResult.fold(
        (failure) => _error = failure.message,
        (lesson) => _currentLesson = lesson,
      );

      _currentExerciseIndex = 0;
      _userAnswers = {};
      _answerResults = {};
      _answerResponses = {};
      _xpEarned = 0;
      _exerciseStartTime = DateTime.now();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> submitAnswer(String answer) async {
    if (_currentLesson == null || isCurrentAnswered) return;
    final exercise = currentExercise;
    if (exercise == null) return;

    _userAnswers[_currentExerciseIndex] = answer;
    final timeSpentMs = _exerciseStartTime != null
        ? DateTime.now().difference(_exerciseStartTime!).inMilliseconds
        : 5000;

    if (_currentAttempt != null) {
      final result = await _submitAnswerUseCase(SubmitAnswerParams(
        attemptId: _currentAttempt!.attemptId,
        questionId: exercise.id,
        questionType: _exerciseTypeToString(exercise.type),
        userAnswer: answer,
        timeSpentMs: timeSpentMs,
      ));

      result.fold(
        (failure) {
          final isCorrect = _checkAnswerLocally(exercise, answer);
          _answerResults[_currentExerciseIndex] = isCorrect;
        },
        (response) {
          _answerResults[_currentExerciseIndex] = response.isCorrect;
          _answerResponses[_currentExerciseIndex] = response;
          _livesRemaining = response.livesRemaining;
          _hintsRemaining = response.hintsRemaining;
          _xpEarned += response.xpEarned;
        },
      );
    } else {
      final isCorrect = _checkAnswerLocally(exercise, answer);
      _answerResults[_currentExerciseIndex] = isCorrect;
      if (isCorrect) {
        _xpEarned += 10;
      } else {
        _livesRemaining = (_livesRemaining - 1).clamp(0, 3);
      }
    }
    notifyListeners();
  }

  void nextExercise() {
    if (_currentLesson == null) return;
    _currentExerciseIndex++;
    _exerciseStartTime = DateTime.now();
    if (_currentExerciseIndex >= totalExercises) {
      _completeLesson();
    }
    notifyListeners();
  }

  void skipExercise() {
    if (_currentLesson == null) return;
    _userAnswers[_currentExerciseIndex] = '';
    _answerResults[_currentExerciseIndex] = false;
    nextExercise();
  }

  void useHint() {
    if (_hintsRemaining > 0) {
      _hintsRemaining--;
      notifyListeners();
    }
  }

  void restartLesson() {
    _currentExerciseIndex = 0;
    _userAnswers = {};
    _answerResults = {};
    _answerResponses = {};
    _xpEarned = 0;
    _livesRemaining = 3;
    _hintsRemaining = 3;
    _lessonResult = null;
    _exerciseStartTime = DateTime.now();
    notifyListeners();
  }

  Future<void> _completeLesson() async {
    if (_currentAttempt == null) {
      final correctAnswers = score;
      final totalQuestions = totalExercises;
      final percentage = totalQuestions > 0 ? (correctAnswers / totalQuestions * 100) : 0.0;
      _xpEarned = (correctAnswers * 10) + (percentage >= 80 ? 20 : 0);
      return;
    }

    final result = await _completeLessonUseCase(CompleteLessonParams(attemptId: _currentAttempt!.attemptId));
    result.fold(
      (failure) => debugPrint('Complete lesson failed: ${failure.message}'),
      (lessonComplete) {
        _lessonResult = lessonComplete;
        _xpEarned = lessonComplete.totalXpEarned;
      },
    );
    notifyListeners();
  }

  bool _checkAnswerLocally(Exercise exercise, String answer) {
    final correctAnswer = exercise.correctAnswer.toLowerCase().trim();
    final userAnswer = answer.toLowerCase().trim();

    switch (exercise.type) {
      case ExerciseType.multipleChoice:
      case ExerciseType.trueFalse:
        return userAnswer == correctAnswer;
      case ExerciseType.fillInBlank:
        return userAnswer == correctAnswer ||
            userAnswer.replaceAll(RegExp(r'[^\w\s]'), '') == correctAnswer.replaceAll(RegExp(r'[^\w\s]'), '');
      case ExerciseType.translate:
        return _calculateSimilarity(userAnswer, correctAnswer) > 0.7;
      default:
        return false;
    }
  }

  String _exerciseTypeToString(ExerciseType type) {
    switch (type) {
      case ExerciseType.multipleChoice: return 'multiple_choice';
      case ExerciseType.trueFalse: return 'true_false';
      case ExerciseType.fillInBlank: return 'fill_blank';
      case ExerciseType.translate: return 'translation';
      case ExerciseType.listening: return 'listening';
      case ExerciseType.speaking: return 'speaking';
    }
  }

  double _calculateSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    final longer = s1.length > s2.length ? s1 : s2;
    final shorter = s1.length > s2.length ? s2 : s1;
    if (longer.isEmpty) return 1.0;
    return (longer.length - _editDistance(longer, shorter)) / longer.length;
  }

  int _editDistance(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;
    final matrix = List.generate(len1 + 1, (i) => List.filled(len2 + 1, 0));
    for (int i = 0; i <= len1; i++) matrix[i][0] = i;
    for (int j = 0; j <= len2; j++) matrix[0][j] = j;
    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost]
            .reduce((a, b) => a < b ? a : b);
      }
    }
    return matrix[len1][len2];
  }

  void clearLesson() {
    _currentLesson = null;
    _currentAttempt = null;
    _currentExerciseIndex = 0;
    _userAnswers = {};
    _answerResults = {};
    _answerResponses = {};
    _xpEarned = 0;
    _livesRemaining = 3;
    _hintsRemaining = 3;
    _lessonResult = null;
    _error = null;
    notifyListeners();
  }
}
