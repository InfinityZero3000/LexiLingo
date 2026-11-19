import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/chat/presentation/utils/topic_icon_resolver.dart';

void main() {
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
