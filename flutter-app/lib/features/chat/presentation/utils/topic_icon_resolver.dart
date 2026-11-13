import 'package:flutter/material.dart';

import '../../domain/entities/story.dart';

class TopicIconResolver {
  const TopicIconResolver._();

  // One icon per category, so the picture means the same thing on every row.
  static IconData forStory(StoryListItem story) =>
      _categoryIcons[story.category.toLowerCase().trim()] ??
      Icons.forum_rounded;

  static const Map<String, IconData> _categoryIcons = {
    'travel': Icons.flight_takeoff,
    'business': Icons.business_center_rounded,
    'work': Icons.work_rounded,
    'daily_life': Icons.home_rounded,
    'housing': Icons.home_rounded,
    'food': Icons.restaurant_rounded,
    'cafe': Icons.local_cafe_rounded,
    'shopping': Icons.shopping_cart_rounded,
    'finance': Icons.account_balance_wallet_rounded,
    'health': Icons.local_hospital_rounded,
    'education': Icons.school_rounded,
    'technology': Icons.devices_rounded,
    'services': Icons.support_agent_rounded,
    'culture': Icons.museum_rounded,
    'leisure': Icons.sports_soccer_rounded,
    'social': Icons.groups_rounded,
    'emergency': Icons.emergency_rounded,
    'environment': Icons.eco_rounded,
    'media': Icons.mic_rounded,
  };
}
