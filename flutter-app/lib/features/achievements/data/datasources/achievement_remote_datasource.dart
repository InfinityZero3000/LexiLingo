/// Achievement Remote Datasource
/// Handles API calls for achievements
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/badge_image_cache.dart';
import 'package:lexilingo_app/features/achievements/data/badge_asset_mapper.dart';
import 'package:lexilingo_app/features/achievements/data/models/achievement_model.dart';

abstract class AchievementRemoteDataSource {
  /// Get all available achievements
  Future<List<AchievementModel>> getAllAchievements();

  /// Get current user's unlocked achievements
  Future<List<UserAchievementModel>> getMyAchievements();

  /// Get recently earned badges (for profile display)
  /// Following agent-skills/gamification-achievement-badges pattern
  Future<List<UserAchievementModel>> getRecentBadges({int limit = 4});

  /// Force check all achievements for current user
  Future<List<UnlockedAchievementModel>> checkAllAchievements();
}

class AchievementRemoteDataSourceImpl implements AchievementRemoteDataSource {
  final ApiClient apiClient;

  AchievementRemoteDataSourceImpl({required this.apiClient});

  Future<void> _warmBadgeCache(List<UserAchievementModel> badges) async {
    final Set<String> urls = <String>{};

    for (final badge in badges) {
      final achievement = badge.achievement;
      final image = resolveBadgeImage(
        slug: achievement.slug ?? achievement.id,
        badgeIcon: achievement.badgeIcon,
      );
      if (image.kind == BadgeImageKind.network) urls.add(image.value!);
    }

    if (urls.isEmpty) return;

    try {
      await Future.wait(
        urls.map(
          (url) => BadgeImageCache.instance
              .downloadFile(url)
              .timeout(BadgeImageCache.networkTimeout),
        ),
      );
    } catch (e) {
      debugPrint('Badge cache warm-up skipped due to error: $e');
    }
  }

  /// A failed call must throw: an empty list here is indistinguishable from
  /// "this learner has no badges" and would overwrite the real list.
  List<dynamic> _items(Map<String, dynamic> data, String what) {
    if (data['success'] != true) {
      throw ServerException('Could not load $what');
    }
    return (data['data'] as List<dynamic>?) ?? const [];
  }

  @override
  Future<List<AchievementModel>> getAllAchievements() async {
    final data = await apiClient.get('/gamification/achievements');
    return _items(
      data,
      'achievements',
    ).map((json) => AchievementModel.fromJson(json)).toList();
  }

  @override
  Future<List<UserAchievementModel>> getMyAchievements() async {
    final data = await apiClient.get('/gamification/achievements/me');
    return _items(
      data,
      'my achievements',
    ).map((json) => UserAchievementModel.fromJson(json)).toList();
  }

  @override
  Future<List<UserAchievementModel>> getRecentBadges({int limit = 4}) async {
    final data = await apiClient.get(
      '/gamification/achievements/recent?limit=$limit',
    );
    final badges = _items(
      data,
      'recent badges',
    ).map((json) => UserAchievementModel.fromJson(json)).toList();
    unawaited(_warmBadgeCache(badges));
    return badges;
  }

  @override
  Future<List<UnlockedAchievementModel>> checkAllAchievements() async {
    final data = await apiClient.post('/gamification/achievements/check');
    return _items(
      data,
      'unlocked achievements',
    ).map((json) => UnlockedAchievementModel.fromJson(json)).toList();
  }
}
