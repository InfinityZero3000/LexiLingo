import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/chat/presentation/utils/topic_icon_resolver.dart';

void main() {
  iconKeyTests();

  test('every category the stories use has its own icon, not the fallback', () {
    const used = [
      'work', 'travel', 'education', 'technology', 'food', 'shopping',
      'services', 'finance', 'health', 'daily_life', 'housing', 'emergency',
      'social', 'business', 'culture', 'leisure', 'media',
    ];
    for (final category in used) {
      expect(
        TopicIconResolver.forCategory(category),
        isNot(Icons.forum_rounded),
        reason: category,
      );
    }
  });

  test('case, padding and spaces do not change the icon', () {
    expect(
      TopicIconResolver.forCategory('  Daily Life '),
      TopicIconResolver.forCategory('daily_life'),
    );
    expect(TopicIconResolver.forCategory('HEALTH'), Icons.local_hospital_rounded);
  });

  test('an unknown or empty category falls back to the generic chat icon', () {
    expect(TopicIconResolver.forCategory('astronomy'), Icons.forum_rounded);
    expect(TopicIconResolver.forCategory(''), Icons.forum_rounded);
  });
}

// Keep in step with ICON_KEYS in ai-service/api/services/topic_meta.py.
const _serviceIconKeys = [
  'travel', 'work', 'business', 'services', 'health', 'food', 'social',
  'finance', 'shopping', 'education', 'technology', 'housing', 'culture',
  'leisure', 'media', 'emergency', 'environment', 'daily_life',
  'hotel', 'directions', 'transport', 'cafe', 'doctor', 'library',
  'classroom', 'internet', 'repair', 'achievement', 'ai', 'chat',
];

void iconKeyTests() {
  group('icon_key', () {
    test('every key the service can send has an icon', () {
      for (final key in _serviceIconKeys.where((k) => k != 'chat')) {
        expect(
          TopicIconResolver.forTopic(iconKey: key, category: 'astronomy'),
          isNot(Icons.forum_rounded),
          reason: key,
        );
      }
    });

    test('a topic icon key beats its category', () {
      expect(
        TopicIconResolver.forTopic(iconKey: 'hotel', category: 'travel'),
        isNot(TopicIconResolver.forCategory('travel')),
      );
    });

    test('a missing or unknown key falls back to the category', () {
      expect(
        TopicIconResolver.forTopic(iconKey: null, category: 'health'),
        Icons.local_hospital_rounded,
      );
      expect(
        TopicIconResolver.forTopic(iconKey: 'bogus', category: 'health'),
        Icons.local_hospital_rounded,
      );
      expect(
        TopicIconResolver.forTopic(iconKey: '  ', category: 'food'),
        Icons.restaurant_rounded,
      );
    });
  });
}
