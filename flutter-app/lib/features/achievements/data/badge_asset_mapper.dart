/// Badge Asset Mapper
/// Maps achievement IDs to custom badge images
/// 
/// Usage:
/// 1. Add badge images to assets/badges/
/// 2. Update pubspec.yaml to include assets
/// 3. Use BadgeAssetMapper.getBadgeAsset(achievementId) to get image path

class BadgeAssetMapper {
  BadgeAssetMapper._();
  
  static const String _basePath = 'assets/badges';
  
  /// Map achievement IDs to their badge image files
  static const Map<String, String> _badgeAssets = {
    // Lesson achievements
    'first_steps': 'lesson_first_steps.png',
    'dedicated_learner': 'lesson_dedicated.png',
    'knowledge_seeker': 'lesson_knowledge.png',
    'scholar': 'lesson_scholar.png',
    'professor': 'lesson_professor.png',
    
    // Streak achievements
    'getting_started': 'streak_3days.png',
    'week_warrior': 'streak_7days.png',
    'two_weeks_strong': 'streak_14days.png',
    'month_master': 'streak_30days.png',
    'quarterly_champion': 'streak_90days.png',
    'year_legend': 'streak_365days.png',
    
    // Vocabulary achievements
    'word_collector': 'vocab_10words.png',
    'vocab_builder': 'vocab_50words.png',
    'vocab_master': 'vocab_100words.png',
    'walking_dictionary': 'vocab_500words.png',
    
    // XP achievements
    'xp_hunter': 'xp_100.png',
    'xp_warrior': 'xp_500.png',
    'xp_champion': 'xp_1000.png',
    'xp_legend': 'xp_5000.png',
    
    // Quiz achievements
    'perfectionist': 'quiz_perfect_1.png',
    'perfect_10': 'quiz_perfect_10.png',
    'flawless': 'quiz_perfect_50.png',
    
    // Course achievements
    'graduate': 'course_1.png',
    'multi_course_master': 'course_5.png',
    
    // Voice achievements
    'voice_starter': 'voice_10.png',
    'voice_pro': 'voice_100.png',
  };
  
  /// Get badge asset path for an achievement
  /// Returns null if no custom asset exists
  static String? getBadgeAsset(String achievementId) {
    final filename = _badgeAssets[achievementId.toLowerCase()];
    if (filename == null) return null;
    return '$_basePath/$filename';
  }
  
  /// Check if achievement has a custom badge image
  static bool hasCustomBadge(String achievementId) {
    return _badgeAssets.containsKey(achievementId.toLowerCase());
  }
  
  /// Get all badge assets that need to be created
  static List<String> getAllRequiredAssets() {
    return _badgeAssets.values.map((f) => '$_basePath/$f').toList();
  }
}

/// Badge image URLs for achievements (can use network images)
/// Use this if you want to host images externally
class BadgeNetworkImages {
  BadgeNetworkImages._();
  
  static const String _baseUrl = 'https://your-cdn.com/badges';
  
  /// Get badge URL for an achievement category
  static String getCategoryBadgeUrl(String category, String rarity) {
    return '$_baseUrl/${category}_$rarity.png';
  }
  
  /// Map of achievement IDs to their badge image URLs
  static const Map<String, String> badgeUrls = {
    // Add URLs when hosting is set up
    // 'first_steps': 'https://your-cdn.com/badges/first_steps.png',
  };
  
  static String? getBadgeUrl(String achievementId) {
    return badgeUrls[achievementId.toLowerCase()];
  }
}
