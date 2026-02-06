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
  /// ✅ = File exists, ❌ = Need to create
  static const Map<String, String> _badgeAssets = {
    // Lesson achievements (4/5 available)
    'first_steps': 'common-lesson.png',        // ✅ Common
    'dedicated_learner': 'common-lesson.png',  // ✅ Common  
    'knowledge_seeker': 'rare-lesson.png',     // ✅ Rare
    'scholar': 'epic-lesson.png',              // ✅ Epic
    'professor': 'legendary-lesson.png',       // ✅ Legendary
    
    // Streak achievements (4/6 available)
    'getting_started': 'streak3.png',          // ✅ 3 days
    'week_warrior': 'streak7.png',             // ✅ 7 days
    'two_weeks_strong': 'streak14.png',        // ❌ Need to create
    'month_master': 'streak30.png',            // ✅ 30 days
    'quarterly_champion': 'streak90.png',      // ❌ Need to create
    'year_legend': 'streak365.png',            // ✅ 365 days
    
    // Vocabulary achievements (4/4 available)
    'word_collector': 'common-vocabulary.png',      // ✅ Common
    'vocab_builder': 'rare-vocabulary.png',         // ✅ Rare
    'vocab_master': 'epic-vocabulary.png',          // ✅ Epic
    'walking_dictionary': 'legendary-vocabulary.png', // ✅ Legendary
    
    // XP achievements (0/4 - Need to create)
    'xp_hunter': 'xp-100.png',         // ❌ 100 XP
    'xp_warrior': 'xp-500.png',        // ❌ 500 XP
    'xp_champion': 'xp-1000.png',      // ❌ 1000 XP
    'xp_legend': 'xp-5000.png',        // ❌ 5000 XP
    
    // Quiz achievements (Perfect Score - 1/3 available)
    'perfectionist': '100%.png',       // ✅ Perfect Score
    'perfect_10': 'perfect-10.png',    // ❌ Need to create
    'flawless': 'perfect-50.png',      // ❌ Need to create
    
    // Course achievements (0/2 - Need to create)
    'graduate': 'course-graduate.png',  // ❌ Complete 1 course
    'multi_course_master': 'course-master.png', // ❌ Complete 5 courses
    
    // Voice achievements (0/2 - Need to create)
    'voice_starter': 'voice-starter.png',  // ❌ 10 recordings
    'voice_pro': 'voice-pro.png',          // ❌ 100 recordings
    
    // Special badges (1 available)
    'night_owl': 'moon.png',           // ✅ Night study badge
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
