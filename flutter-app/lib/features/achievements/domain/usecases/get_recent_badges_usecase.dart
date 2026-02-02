/// Get Recent Badges UseCase
/// 
/// Following agent-skills/language-learning-patterns:
/// - gamification-achievement-badges: Display recent badges for engagement (25-40% boost)
/// - Users respond well to seeing their recent accomplishments prominently displayed

import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/domain/repositories/achievement_repository.dart';

class GetRecentBadgesUseCase {
  final AchievementRepository repository;

  GetRecentBadgesUseCase({required this.repository});

  /// Get user's most recently earned badges
  /// 
  /// [limit] - Maximum number of badges to return (default: 4)
  /// Returns list sorted by unlocked_at DESC
  Future<List<UserAchievementEntity>> call({int limit = 4}) async {
    return await repository.getRecentBadges(limit: limit);
  }
}
