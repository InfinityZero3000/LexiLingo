import 'package:flutter/material.dart';

import '../../data/datasources/proficiency_data_source.dart';

/// Provider for managing placement test state
class PlacementTestProvider with ChangeNotifier {
  final ProficiencyDataSource _dataSource;

  PlacementTestProvider({required ProficiencyDataSource dataSource})
      : _dataSource = dataSource;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<Map<String, dynamic>> _questions = [];
  List<Map<String, dynamic>> get questions => _questions;

  Map<String, dynamic>? _result;
  Map<String, dynamic>? get result => _result;

  /// Load the placement test questions
  Future<void> loadTest() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _dataSource.getPlacementTest();
      _questions = List<Map<String, dynamic>>.from(response['questions'] ?? []);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load test: ${e.toString()}';
      _questions = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Submit the test answers
  /// [answers] is a map of question_id -> selected_answer_index
  /// Returns true if submission was successful
  Future<bool> submitTest(Map<String, int> answers, int timeTakenSeconds) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _dataSource.submitPlacementTest(
        answers: answers,
        timeTakenSeconds: timeTakenSeconds,
      );
      _result = response;
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = 'Failed to submit test: ${e.toString()}';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reset the provider state
  void reset() {
    _questions = [];
    _result = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }
}
