/// Badge Asset Mapper
/// Maps achievement IDs to custom badge images in assets/badges/
///
/// All badge PNG files are mapped to achievement IDs.
/// The AchievementBadge widget uses this to show image assets
/// and falls back to SmartAchievementBadge if no mapping exists.

class BadgeAssetMapper {
  BadgeAssetMapper._();

  static const String _basePath = 'assets/badges';

  /// Map achievement IDs to their badge image files
  static const Map<String, String> _badgeAssets = {
    // ===================== LESSON ACHIEVEMENTS =====================
    'first_steps': 'common-lesson.png',
    'dedicated_learner': 'common-lesson.png',
    'knowledge_seeker': 'rare-lesson.png',
    'scholar': 'epic-lesson.png',
    'professor': 'legendary-lesson.png',

    // ===================== STREAK ACHIEVEMENTS =====================
    'getting_started': 'streak3.png',
    'week_warrior': 'streak7.png',
    'two_weeks_strong': 'streak30.png',
    'month_master': 'streak30.png',
    'quarterly_champion': 'streak90.png',
    'year_legend': 'streak365.png',

    // ===================== VOCABULARY ACHIEVEMENTS =================
    'word_collector': 'common-vocabulary.png',
    'vocab_builder': 'rare-vocabulary.png',
    'vocab_master': 'epic-vocabulary.png',
    'walking_dictionary': 'legendary-vocabulary.png',

    // ===================== QUIZ / PERFECT SCORE ====================
    'perfectionist': '100%.png',
    'first_perfect_score': 'first-perfect.png',
    'accuracy_master': 'perfect-10.png',
    'flawless': 'perfect-50.png',
    'quiz_champion': 'quiz-champion.png',

    // ===================== COURSE ACHIEVEMENTS =====================
    'course_explorer': 'course-graduate.png',
    'course_champion': 'course-master.png',

    // ===================== VOICE ACHIEVEMENTS ======================
    'voice_beginner': 'voice-starter.png',
    'voice_talent': 'voice-pro.png',
    'pronunciation_master': 'pronunciation-pro.png',

    // ===================== LEVEL MILESTONES ========================
    'level_25': 'lv25.png',
    'level_50': 'lv50.png',
    'level_100': 'lv100.png',
    'level_150': 'lv150.png',
    'level_200': 'lv200.png',
    'level_300': 'lv300.png',
    'level_500': 'lv500.png',

    // ===================== SPECIAL — TIME-BASED ====================
    'night_owl': 'moon.png',
    'early_bird': 'early-bird.png',
    'speed_demon': 'speed-demon.png',

    // ===================== SPECIAL — SKILL MASTERY =================
    'grammar_guardian': 'grammar-guardian.png',
    'culture_explorer': 'culture-explorer.png',
    'writing_wizard': 'writing-wizard.png',
    'listening_legend': 'listening-legend.png',

    // ===================== SPECIAL — SOCIAL ========================
    'social_butterfly': 'social-butterfly.png',
    'conversation_champion': 'conversation-champion.png',
    'feedback_friend': 'feedback-friend.png',

    // ===================== SPECIAL — MILESTONES ====================
    'challenge_crusher': 'challenge-crusher.png',
    'milestone_maker': 'milestone-maker.png',
    'comeback_king': 'comeback-king.png',
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
