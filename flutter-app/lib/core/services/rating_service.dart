import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RatingService {
  static final RatingService instance = RatingService._();
  RatingService._();

  static const String _countKey = 'lessons_completed_total';
  static const String _ratingShownKey = 'rating_prompt_shown';
  static const int _triggerThreshold = 5;

  Future<void> onLessonCompleted() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyShown = prefs.getBool(_ratingShownKey) ?? false;
      if (alreadyShown) return;

      final count = (prefs.getInt(_countKey) ?? 0) + 1;
      await prefs.setInt(_countKey, count);

      if (count >= _triggerThreshold) {
        final inAppReview = InAppReview.instance;
        if (await inAppReview.isAvailable()) {
          await inAppReview.requestReview();
          await prefs.setBool(_ratingShownKey, true);
        }
      }
    } catch (e) {
      debugPrint('RatingService: $e');
    }
  }

  Future<void> openStoreListing() async {
    final inAppReview = InAppReview.instance;
    await inAppReview.openStoreListing();
  }
}
