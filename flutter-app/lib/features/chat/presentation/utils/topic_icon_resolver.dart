import 'package:flutter/material.dart';

import '../../data/models/story_model.dart';

class TopicIconResolver {
  const TopicIconResolver._();

  static IconData forStory(StoryListItem story) {
    final haystack = [
      story.iconKey,
      story.category,
      story.title.en,
      story.title.vi,
      ...story.tags,
    ].whereType<String>().join(' ').toLowerCase().replaceAll('_', ' ');

    for (final entry in _keywordIcons.entries) {
      if (haystack.contains(entry.key)) return entry.value;
    }

    return _categoryIcons[story.category.toLowerCase().trim()] ??
        Icons.forum_rounded;
  }

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

  static const Map<String, IconData> _keywordIcons = {
    'airport': Icons.flight_takeoff,
    'travel': Icons.flight_takeoff,
    'hotel': Icons.hotel_rounded,
    'direction': Icons.explore_rounded,
    'directions': Icons.explore_rounded,
    'transport': Icons.directions_car_rounded,
    'train': Icons.train_rounded,
    'luggage': Icons.luggage_rounded,
    'customs': Icons.assignment_turned_in_rounded,
    'immigration': Icons.badge_rounded,
    'city tour': Icons.tour_rounded,
    'car rental': Icons.directions_car_rounded,
    'emergency': Icons.emergency_rounded,
    'standup': Icons.groups_rounded,
    'meeting': Icons.forum_rounded,
    'presentation': Icons.co_present_rounded,
    'salary': Icons.payments_rounded,
    'performance review': Icons.rate_review_rounded,
    'networking': Icons.handshake_rounded,
    'remote work': Icons.laptop_mac_rounded,
    'customer support': Icons.support_agent_rounded,
    'doctor': Icons.medical_services_rounded,
    'pharmacy': Icons.medication_rounded,
    'dental': Icons.medical_services_rounded,
    'mental health': Icons.psychology_rounded,
    'fitness': Icons.fitness_center_rounded,
    'insurance': Icons.health_and_safety_rounded,
    'grocery': Icons.local_grocery_store_rounded,
    'cooking': Icons.soup_kitchen_rounded,
    'delivery': Icons.delivery_dining_rounded,
    'bakery': Icons.bakery_dining_rounded,
    'dietary': Icons.no_meals_rounded,
    'dinner party': Icons.celebration_rounded,
    'bank': Icons.account_balance_rounded,
    'phone plan': Icons.smartphone_rounded,
    'electronics': Icons.devices_other_rounded,
    'online order': Icons.receipt_long_rounded,
    'prices': Icons.price_check_rounded,
    'budget': Icons.savings_rounded,
    'loan': Icons.request_quote_rounded,
    'tax': Icons.calculate_rounded,
    'university': Icons.school_rounded,
    'classroom': Icons.school_rounded,
    'library': Icons.local_library_rounded,
    'teacher': Icons.escalator_warning_rounded,
    'study group': Icons.diversity_3_rounded,
    'exam': Icons.quiz_rounded,
    'scholarship': Icons.workspace_premium_rounded,
    'debate': Icons.record_voice_over_rounded,
    'password': Icons.password_rounded,
    'bug': Icons.bug_report_rounded,
    'privacy': Icons.privacy_tip_rounded,
    'laptop': Icons.laptop_mac_rounded,
    'cybersecurity': Icons.security_rounded,
    'ai product': Icons.smart_toy_rounded,
    'sprint': Icons.task_alt_rounded,
    'moving': Icons.local_shipping_rounded,
    'plumber': Icons.plumbing_rounded,
    'repair': Icons.plumbing_rounded,
    'utility bill': Icons.receipt_long_rounded,
    'cleaning': Icons.cleaning_services_rounded,
    'neighborhood': Icons.home_work_rounded,
    'internet': Icons.wifi_rounded,
    'museum': Icons.museum_rounded,
    'sports club': Icons.sports_soccer_rounded,
    'volunteering': Icons.volunteer_activism_rounded,
    'news interview': Icons.mic_rounded,
    'achievement': Icons.workspace_premium_rounded,
    'ai': Icons.smart_toy_rounded,
    'chat': Icons.forum_rounded,
  };
}
