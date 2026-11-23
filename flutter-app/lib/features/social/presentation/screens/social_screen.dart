import 'dart:math' as math;
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Social Screen
/// Activity feed and friends management
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _feedScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _feedScrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SocialProvider>();
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.user?.id ?? '';

      provider.loadActivityFeed(refresh: true);
      provider.loadSuggestedUsers();
      provider.loadNearbyUsers();
      if (userId.isNotEmpty) {
        provider.loadFollowers(userId, refresh: true);
        provider.loadFollowing(userId, refresh: true);
      }
    });
  }

  void _onScroll() {
    if (_feedScrollController.position.pixels >=
        _feedScrollController.position.maxScrollExtent * 0.9) {
      final provider = context.read<SocialProvider>();
      if (provider.hasMoreFeed && !provider.isLoadingFeed) {
        provider.loadActivityFeed();
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _feedScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Scaffold(
      appBar: AppBar(
        title: Text('social.friends'.tr()),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: primaryColor,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          indicatorColor: primaryColor,
          // Three tabs share 390 px; the default 16 px label padding clipped
          // "Người theo dõi" by two pixels.
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          tabs: [
            for (final key in const [
              'social.feedTab',
              'social.followersTab',
              'social.followingTab',
            ])
              Tab(
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(key.tr())),
              ),
          ],
        ),
      ),
      body: ContentWidth(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildFeedTab(),
            _buildFollowersTab(),
            _buildFollowingTab(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showSearchSheet,
        backgroundColor: primaryColor,
        child: Icon(
          Icons.person_add,
          color: Theme.of(context).colorScheme.surface,
        ),
      ),
    );
  }

  Widget _buildFeedTab() {
    return Consumer<SocialProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingFeed && provider.activityFeed.isEmpty) {
          return const Center(child: LottieLoadingWidget.medium());
        }

        if (provider.feedError != null && provider.activityFeed.isEmpty) {
          return ErrorDisplayWidget.fromMessage(
            message: provider.feedError!,
            onRetry: () => provider.loadActivityFeed(refresh: true),
          );
        }

        if (provider.activityFeed.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              await provider.loadActivityFeed(refresh: true);
              await provider.loadSuggestedUsers();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 80),
              child: Column(
                children: [
                  _SuggestedFriendsSection(
                    users: provider.suggestedUsers,
                    isLoading: provider.isLoadingSuggestions,
                    onFollowToggle: _toggleFollow,
                    onRefresh: provider.loadSuggestedUsers,
                  ),
                  _buildEmptyFeed(),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await provider.loadActivityFeed(refresh: true);
            await provider.loadSuggestedUsers();
            await provider.loadNearbyUsers();
          },
          child: ListView.builder(
            controller: _feedScrollController,
            padding: const EdgeInsets.only(bottom: 80),
            itemCount:
                provider.activityFeed.length +
                (provider.isLoadingFeed ? 1 : 0) +
                2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _NearbyLearnersSection(
                  users: provider.nearbyUsers,
                  isLoading: provider.isLoadingNearby,
                  isEnabled: provider.isNearbyEnabled,
                  error: provider.nearbyError,
                  onFollowToggle: _toggleFollow,
                  onRefresh: provider.loadNearbyUsers,
                  onDisable: provider.disableNearbySharing,
                );
              }

              if (index == 1) {
                return _SuggestedFriendsSection(
                  users: provider.suggestedUsers,
                  isLoading: provider.isLoadingSuggestions,
                  onFollowToggle: _toggleFollow,
                  onRefresh: provider.loadSuggestedUsers,
                );
              }

              final feedIndex = index - 2;

              if (feedIndex == provider.activityFeed.length &&
                  provider.isLoadingFeed) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: LottieLoadingWidget.tiny(),
                  ),
                );
              }

              final activity = provider.activityFeed[feedIndex];
              return _ActivityFeedCard(activity: activity);
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyFeed() {
    return EmptyStateWidget(
      icon: Icons.people_outline,
      iconSize: 48,
      title: 'social.noActivityYet'.tr(),
      description: 'social.followFriendsToSeeActivity'.tr(),
      actionLabel: 'social.findFriends'.tr(),
      onAction: _showSearchSheet,
    );
  }

  Widget _buildFollowersTab() {
    return Consumer<SocialProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingFollowers && provider.followers.isEmpty) {
          return const Center(child: LottieLoadingWidget.medium());
        }

        if (provider.followers.isEmpty) {
          return EmptyStateWidget(title: 'social.noFollowersYet'.tr());
        }

        return RefreshIndicator(
          onRefresh: () async {
            final userId = context.read<AuthProvider>().user?.id ?? '';
            await provider.loadFollowers(userId, refresh: true);
          },
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: provider.followers.length,
            itemBuilder: (context, index) {
              final user = provider.followers[index];
              return _UserProfileCard(
                user: user,
                onFollowToggle: () => _toggleFollow(user),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFollowingTab() {
    return Consumer<SocialProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingFollowing && provider.following.isEmpty) {
          return const Center(child: LottieLoadingWidget.medium());
        }

        if (provider.following.isEmpty) {
          return EmptyStateWidget(
            title: 'social.notFollowingAnyone'.tr(),
            actionLabel: 'social.findFriends'.tr(),
            onAction: _showSearchSheet,
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            final userId = context.read<AuthProvider>().user?.id ?? '';
            await provider.loadFollowing(userId, refresh: true);
          },
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: provider.following.length,
            itemBuilder: (context, index) {
              final user = provider.following[index];
              return _UserProfileCard(
                user: user,
                onFollowToggle: () => _toggleFollow(user),
                showUnfollow: true,
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _toggleFollow(UserSocialProfileEntity user) async {
    final provider = context.read<SocialProvider>();

    final String? error;
    if (user.isFollowing) {
      error = await provider.unfollowUser(user.userId);
    } else {
      error = await provider.followUser(user.userId);
    }

    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0),
      builder: (context) =>
          _SearchUsersSheet(onFollow: (user) => _toggleFollow(user)),
    );
  }
}

class _SuggestedFriendsSection extends StatelessWidget {
  final List<UserSocialProfileEntity> users;
  final bool isLoading;
  final Future<void> Function({int limit}) onRefresh;
  final Future<void> Function(UserSocialProfileEntity user) onFollowToggle;

  const _SuggestedFriendsSection({
    required this.users,
    required this.isLoading,
    required this.onRefresh,
    required this.onFollowToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: primaryColor.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: primaryColor, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'social.suggestedFriends'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColorRoles.textPrimary(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: isLoading ? null : () => onRefresh(limit: 10),
                icon: const Icon(Icons.refresh, size: 18),
                color: primaryColor,
                tooltip: 'social.refreshSuggestions'.tr(),
              ),
            ],
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LottieLoadingWidget.tiny(),
            )
          else if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'social.noSuggestionsNow'.tr(),
                style: TextStyle(color: AppColorRoles.textMuted(isDark)),
              ),
            )
          else
            Column(
              children: users.take(5).map((user) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: primaryColor.withValues(alpha: 0.12),
                    child: Text(
                      user.displayName.isNotEmpty
                          ? user.displayName[0].toUpperCase()
                          : user.username[0].toUpperCase(),
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    user.suggestionReasons
                        .take(2)
                        .map(_formatSuggestionReason)
                        .join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () => onFollowToggle(user),
                    child: Text(
                      user.isFollowing
                          ? 'social.following'.tr()
                          : 'social.follow'.tr(),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

String _formatSuggestionReason(String reason) {
  const map = {
    'same_cefr': 'social.sameLevel',
    'similar_xp': 'social.similarXp',
    'same_target_language': 'social.sameTargetLanguage',
    'same_native_language': 'social.sameNativeLanguage',
    'mutual_friends': 'social.mutualFriends',
    'nearby': 'social.nearbyReason',
  };
  final key = map[reason];
  return key != null ? key.tr() : reason;
}

class _NearbyLearnersSection extends StatelessWidget {
  final List<UserSocialProfileEntity> users;
  final bool isLoading;
  final bool isEnabled;
  final String? error;
  final Future<void> Function({int limit, double radiusKm}) onRefresh;
  final Future<void> Function(UserSocialProfileEntity user) onFollowToggle;
  final Future<void> Function() onDisable;

  const _NearbyLearnersSection({
    required this.users,
    required this.isLoading,
    required this.isEnabled,
    required this.error,
    required this.onRefresh,
    required this.onFollowToggle,
    required this.onDisable,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: context.status.success.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.near_me, color: context.status.success, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'social.nearbyLearners'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColorRoles.textPrimary(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              if (isEnabled)
                IconButton(
                  onPressed: isLoading ? null : onDisable,
                  icon: const Icon(Icons.location_disabled, size: 18),
                  tooltip: 'social.disableNearby'.tr(),
                  color: AppColorRoles.textMuted(isDark),
                ),
              IconButton(
                onPressed: isLoading
                    ? null
                    : () => onRefresh(limit: 10, radiusKm: 25),
                icon: const Icon(Icons.refresh, size: 18),
                color: primaryColor,
                tooltip: 'social.refreshNearby'.tr(),
              ),
            ],
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LottieLoadingWidget.tiny(),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                error!,
                style: TextStyle(color: AppColorRoles.textMuted(isDark)),
              ),
            )
          else if (!isEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'social.enableLocationNearby'.tr(),
                style: TextStyle(color: AppColorRoles.textMuted(isDark)),
              ),
            )
          else if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'social.noNearbyLearners'.tr(),
                style: TextStyle(color: AppColorRoles.textMuted(isDark)),
              ),
            )
          else
            Column(
              children: users.take(5).map((user) {
                final distance = user.distanceKm != null
                    ? '${user.distanceKm!.toStringAsFixed(1)} km'
                    : 'social.nearbyReason'.tr();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: context.status.success.withValues(
                      alpha: 0.12,
                    ),
                    child: Text(
                      user.displayName.isNotEmpty
                          ? user.displayName[0].toUpperCase()
                          : user.username[0].toUpperCase(),
                      style: TextStyle(
                        color: context.status.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    distance,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () => onFollowToggle(user),
                    child: Text(
                      user.isFollowing
                          ? 'social.following'.tr()
                          : 'social.follow'.tr(),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

/// Activity Feed Card
class _ActivityFeedCard extends StatelessWidget {
  final ActivityFeedItemEntity activity;

  const _ActivityFeedCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: (Theme.of(
              context,
            ).colorScheme.outlineVariant).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor.withValues(alpha: 0.1),
              border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
            ),
            child: activity.avatarUrl != null && activity.avatarUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      activity.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildInitial(context),
                    ),
                  )
                : _buildInitial(context),
          ),
          const SizedBox(width: AppSpacing.md),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text: activity.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const TextSpan(text: ' '),
                            TextSpan(
                              text: activity.message,
                              style: TextStyle(
                                color: AppColorRoles.textSecondary(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(
                      _getActivityIcon(),
                      size: 14,
                      color: _getActivityColor(context),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _formatTime(activity.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColorRoles.textMuted(isDark),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitial(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Text(
        activity.displayName.isNotEmpty
            ? activity.displayName[0].toUpperCase()
            : activity.username[0].toUpperCase(),
        style: Theme.of(context).textTheme.sectionTitle?.copyWith(
          fontWeight: FontWeight.bold,
          color: AppColorRoles.primary(isDark),
        ),
      ),
    );
  }

  IconData _getActivityIcon() {
    switch (activity.activityType) {
      case ActivityFeedItemEntity.typeAchievement:
        return Icons.emoji_events;
      case ActivityFeedItemEntity.typeCourse:
        return Icons.school;
      case ActivityFeedItemEntity.typeLesson:
        return Icons.menu_book;
      case ActivityFeedItemEntity.typeStreak:
        return Icons.local_fire_department;
      case ActivityFeedItemEntity.typeLevel:
        return Icons.arrow_upward;
      default:
        return Icons.star;
    }
  }

  Color _getActivityColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (activity.activityType) {
      case ActivityFeedItemEntity.typeAchievement:
        return AppColors.gold;
      case ActivityFeedItemEntity.typeCourse:
        return context.status.success;
      case ActivityFeedItemEntity.typeLesson:
        return AppColorRoles.primary(isDark);
      case ActivityFeedItemEntity.typeStreak:
        return AppColors.orange;
      case ActivityFeedItemEntity.typeLevel:
        return AppColors.purple;
      default:
        return AppColorRoles.primary(isDark);
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return 'datetime.justNow'.tr();
    }
    if (diff.inHours < 1) {
      return 'datetime.minutesAgo'.tr(
        namedArgs: {'minutes': diff.inMinutes.toString()},
      );
    }
    if (diff.inDays < 1) {
      return 'datetime.hoursAgo'.tr(
        namedArgs: {'hours': diff.inHours.toString()},
      );
    }
    if (diff.inDays < 7) {
      return 'datetime.daysAgo'.tr(namedArgs: {'days': diff.inDays.toString()});
    }
    return DateFormat('MMM d').format(date);
  }
}

/// User Profile Card
class _UserProfileCard extends StatelessWidget {
  final UserSocialProfileEntity user;
  final VoidCallback onFollowToggle;
  final bool showUnfollow;

  const _UserProfileCard({
    required this.user,
    required this.onFollowToggle,
    this.showUnfollow = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: (Theme.of(
              context,
            ).colorScheme.outlineVariant).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor.withValues(alpha: 0.1),
            ),
            child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      user.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildInitial(context),
                    ),
                  )
                : _buildInitial(context),
          ),
          const SizedBox(width: AppSpacing.md),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '@${user.username}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColorRoles.textMuted(isDark),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    if (user.currentStreak > 0) ...[
                      Icon(
                        Icons.local_fire_department,
                        size: 14,
                        color: AppColors.orange,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${user.currentStreak}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorRoles.textMuted(isDark),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Text(
                      '${user.xp} XP',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColorRoles.textMuted(isDark),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Follow Button
          GestureDetector(
            onTap: onFollowToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: user.isFollowing
                    ? (Theme.of(context).colorScheme.surfaceContainerHighest)
                    : primaryColor,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Text(
                user.isFollowing
                    ? (showUnfollow
                          ? 'social.unfollow'.tr()
                          : 'social.following'.tr())
                    : 'social.follow'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: user.isFollowing
                      ? AppColorRoles.textSecondary(isDark)
                      : Theme.of(context).colorScheme.surface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitial(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Text(
        user.displayName.isNotEmpty
            ? user.displayName[0].toUpperCase()
            : user.username[0].toUpperCase(),
        style: Theme.of(context).textTheme.sectionTitle?.copyWith(
          fontWeight: FontWeight.bold,
          color: AppColorRoles.primary(isDark),
        ),
      ),
    );
  }
}

/// Search Users Bottom Sheet
class _SearchUsersSheet extends StatefulWidget {
  final Function(UserSocialProfileEntity) onFollow;

  const _SearchUsersSheet({required this.onFollow});

  @override
  State<_SearchUsersSheet> createState() => _SearchUsersSheetState();
}

class _SearchUsersSheetState extends State<_SearchUsersSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The provider outlives the sheet; without this a reopened sheet shows the
    // last query's results above an empty field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SocialProvider>().clearSearch();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final available = media.size.height - keyboard - media.padding.top;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        height: math.min(media.size.height * 0.8, available),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'social.findFriends'.tr(),
                    style: Theme.of(context).textTheme.sectionTitle?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Search field
                  TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'social.searchByUsername'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _controller.clear();
                                setState(() {});
                                context.read<SocialProvider>().clearSearch();
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {});
                      context.read<SocialProvider>().searchUsers(value);
                    },
                  ),
                ],
              ),
            ),

            // Results
            Expanded(
              child: Consumer<SocialProvider>(
                builder: (context, provider, child) {
                  if (provider.isSearching) {
                    return const Center(child: LottieLoadingWidget.medium());
                  }

                  if (provider.searchError != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            provider.searchError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColorRoles.textMuted(isDark),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (provider.searchQuery.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'social.searchForFriends'.tr(),
                            style: TextStyle(
                              color: AppColorRoles.textMuted(isDark),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (provider.searchResults.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'social.noUsersFound'.tr(),
                            style: TextStyle(
                              color: AppColorRoles.textMuted(isDark),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: provider.searchResults.length,
                    itemBuilder: (context, index) {
                      final user = provider.searchResults[index];
                      return _UserProfileCard(
                        user: user,
                        onFollowToggle: () => widget.onFollow(user),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
