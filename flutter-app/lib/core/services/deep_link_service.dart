import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/services/app_navigation_service.dart';

/// Handles incoming deep links and universal links.
///
/// URL scheme: lexilingo://  or  https://lexilingo.app/
///
/// Supported paths:
///   /course/{id}          → navigate to course roadmap
///   /lesson/{id}          → start a lesson
///   /vocabulary/review    → open flashcard review
///   /leaderboard          → open leaderboard tab
///   /achievement/{id}     → open achievements screen
///   /referral/{code}      → store referral code, claim after sign-in
class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._();
  DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// Referral code received before the user was signed in.
  String? pendingReferralCode;

  /// Reset token received before the navigator was ready (cold-start).
  String? pendingResetToken;

  Future<void> init() async {
    // Handle cold-start link (app launched from a link)
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _route(initial);
    } catch (e) {
      debugPrint('DeepLinkService initial link error: $e');
    }

    // Handle links when app is already open
    _sub = _appLinks.uriLinkStream.listen(
      _route,
      onError: (e) => debugPrint('DeepLinkService stream error: $e'),
    );
  }

  void dispose() => _sub?.cancel();

  void _route(Uri uri) {
    debugPrint('DeepLink: $uri');
    final segments = uri.pathSegments;

    if (segments.isEmpty) return;

    switch (segments[0]) {
      case 'course':
        if (segments.length > 1) {
          AppNavigationService.openRoute('/course/${segments[1]}');
        }
      case 'lesson':
        if (segments.length > 1) {
          AppNavigationService.openRoute('/lesson/${segments[1]}');
        }
      case 'vocabulary':
        if (segments.length > 1 && segments[1] == 'review') {
          AppNavigationService.openRoute('/vocabulary/review');
        }
      case 'leaderboard':
        AppNavigationService.openRoute('/leaderboard');
      case 'achievement':
        AppNavigationService.openRoute('/achievements');
      case 'reset-password':
        final token = uri.queryParameters['token'];
        if (token != null && token.isNotEmpty) {
          pendingResetToken = token;
          AppNavigationService.openRoute('/reset-password', arguments: token);
        }
      case 'referral':
        if (segments.length > 1) {
          pendingReferralCode = segments[1];
          debugPrint('Referral code stored: $pendingReferralCode');
        }
      default:
        debugPrint('DeepLink: unhandled path ${uri.path}');
    }
  }
}
