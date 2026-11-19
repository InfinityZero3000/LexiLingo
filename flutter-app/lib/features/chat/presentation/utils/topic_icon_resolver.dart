import 'package:flutter/material.dart';

import '../../domain/entities/story.dart';

class TopicIconResolver {
  const TopicIconResolver._();

  // The admin picks (or the service infers) an icon key per topic; without one
  // the category decides, so the picture means the same thing on every row.
  static IconData forStory(StoryListItem story) =>
      forTopic(iconKey: story.iconKey, category: story.category);

  static IconData forTopic({String? iconKey, required String category}) =>
      _iconKeys[_normalize(iconKey ?? '')] ?? forCategory(category);

  static IconData forCategory(String category) =>
      _categoryIcons[_normalize(category)] ?? Icons.forum_rounded;

  static String _normalize(String value) =>
      value.toLowerCase().trim().replaceAll(' ', '_');

  // Keys beyond the categories; mirrors ICON_KEYS in ai-service topic_meta.py.
  static const Map<String, IconData> _iconKeys = {
    ..._categoryIcons,
    'hotel': Icons.hotel_rounded,
    'directions': Icons.directions_rounded,
    'transport': Icons.directions_transit_rounded,
    'doctor': Icons.medical_services_rounded,
    'library': Icons.local_library_rounded,
    'classroom': Icons.class_rounded,
    'internet': Icons.wifi_rounded,
    'repair': Icons.build_rounded,
    'achievement': Icons.emoji_events_rounded,
    'ai': Icons.auto_awesome_rounded,
    'chat': Icons.forum_rounded,
  };

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
