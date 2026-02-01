import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';

/// Daily Challenges Provider
/// Manages daily challenges state for gamification UI
/// Clean Architecture: Presentation layer state management
class DailyChallengesProvider extends ChangeNotifier {
  final ProgressRepository _repository;

  DailyChallengesProvider({required ProgressRepository repository})
      : _repository = repository;

  // State
  DailyChallengesResponse? _challengesResponse;
  bool _isLoading = false;
  String? _errorMessage;
  Set<String> _claimedRewards = {};

  // Getters
  DailyChallengesResponse? get challengesResponse => _challengesResponse;
  List<DailyChallengeEntity> get challenges =>
      _challengesResponse?.challenges ?? [];
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Total number of challenges
  int get totalChallenges => _challengesResponse?.totalChallenges ?? 0;

  /// Number of completed challenges
  int get completedCount => _challengesResponse?.totalCompleted ?? 0;

  /// Whether all challenges are completed
  bool get allCompleted => _challengesResponse?.allCompleted ?? false;

  /// Bonus XP for completing all challenges
  int get bonusXp => _challengesResponse?.bonusXp ?? 0;

  /// Total XP earned so far
  int get xpEarned => _challengesResponse?.xpEarned ?? 0;

  /// Total available XP
  int get totalXpAvailable => _challengesResponse?.totalXpAvailable ?? 0;

  /// Progress as percentage (0.0 - 1.0)
  double get progress => _challengesResponse?.progress ?? 0.0;

  /// Check if a reward has been claimed
  bool isRewardClaimed(String challengeId) => _claimedRewards.contains(challengeId);

  /// Load daily challenges from API
  Future<void> loadChallenges() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getDailyChallenges();

    result.fold(
      (failure) {
        _errorMessage = failure.message;
      },
      (response) {
        _challengesResponse = response;
        // Reset claimed rewards for new day
        if (_challengesResponse != null) {
          _claimedRewards.clear();
        }
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  /// Claim reward for a completed challenge
  Future<bool> claimReward(String challengeId) async {
    // Check if already claimed
    if (_claimedRewards.contains(challengeId)) {
      _errorMessage = 'Reward already claimed';
      notifyListeners();
      return false;
    }

    // Find the challenge
    final challenge = challenges.firstWhere(
      (c) => c.id == challengeId,
      orElse: () => throw Exception('Challenge not found'),
    );

    // Check if completed
    if (!challenge.isCompleted) {
      _errorMessage = 'Challenge not completed yet';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    final result = await _repository.claimChallengeReward(challengeId);

    bool success = false;
    result.fold(
      (failure) {
        _errorMessage = failure.message;
      },
      (data) {
        _claimedRewards.add(challengeId);
        success = true;
      },
    );

    _isLoading = false;
    notifyListeners();
    return success;
  }

  /// Refresh challenges (reload from API)
  Future<void> refresh() async {
    await loadChallenges();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset state (for logout)
  void reset() {
    _challengesResponse = null;
    _isLoading = false;
    _errorMessage = null;
    _claimedRewards.clear();
    notifyListeners();
  }
}
