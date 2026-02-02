import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textGrey,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Feed'),
            Tab(text: 'Followers'),
            Tab(text: 'Following'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFeedTab(),
          _buildFollowersTab(),
          _buildFollowingTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showSearchSheet,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }

  Widget _buildFeedTab() {
    return Consumer<SocialProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingFeed && provider.activityFeed.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.feedError != null && provider.activityFeed.isEmpty) {
          return ErrorDisplayWidget.fromMessage(
            message: provider.feedError!,
            onRetry: () => provider.loadActivityFeed(refresh: true),
          );
        }

        if (provider.activityFeed.isEmpty) {
          return _buildEmptyFeed();
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadActivityFeed(refresh: true),
          child: ListView.builder(
            controller: _feedScrollController,
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: provider.activityFeed.length +
                (provider.isLoadingFeed ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == provider.activityFeed.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final activity = provider.activityFeed[index];
              return _ActivityFeedCard(activity: activity);
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyFeed() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text(
            'No activity yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Follow friends to see their activity!',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showSearchSheet,
            icon: const Icon(Icons.person_add),
            label: const Text('Find Friends'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowersTab() {
    return Consumer<SocialProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingFollowers && provider.followers.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.followers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text('No followers yet'),
              ],
            ),
          );
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
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.following.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text('Not following anyone yet'),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _showSearchSheet,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Find Friends'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
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
    
    if (user.isFollowing) {
      await provider.unfollowUser(user.userId);
    } else {
      await provider.followUser(user.userId);
    }
  }

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SearchUsersSheet(
        onFollow: (user) => _toggleFollow(user),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
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
              color: AppColors.primary.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: activity.avatarUrl != null && activity.avatarUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      activity.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildInitial(),
                    ),
                  )
                : _buildInitial(),
          ),
          const SizedBox(width: 12),

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
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const TextSpan(text: ' '),
                            TextSpan(
                              text: activity.message,
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      _getActivityIcon(),
                      size: 14,
                      color: _getActivityColor(),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatTime(activity.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
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

  Widget _buildInitial() {
    return Center(
      child: Text(
        activity.displayName.isNotEmpty
            ? activity.displayName[0].toUpperCase()
            : activity.username[0].toUpperCase(),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
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

  Color _getActivityColor() {
    switch (activity.activityType) {
      case ActivityFeedItemEntity.typeAchievement:
        return const Color(0xFFFFD700);
      case ActivityFeedItemEntity.typeCourse:
        return const Color(0xFF10B981);
      case ActivityFeedItemEntity.typeLesson:
        return const Color(0xFF3B82F6);
      case ActivityFeedItemEntity.typeStreak:
        return const Color(0xFFF59E0B);
      case ActivityFeedItemEntity.typeLevel:
        return const Color(0xFF8B5CF6);
      default:
        return AppColors.primary;
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
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
              color: AppColors.primary.withValues(alpha: 0.1),
            ),
            child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      user.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildInitial(),
                    ),
                  )
                : _buildInitial(),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '@${user.username}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (user.currentStreak > 0) ...[
                      Icon(
                        Icons.local_fire_department,
                        size: 14,
                        color: Colors.orange[400],
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${user.currentStreak}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '${user.xp} XP',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: user.isFollowing
                    ? Colors.grey[200]
                    : AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                user.isFollowing
                    ? (showUnfollow ? 'Unfollow' : 'Following')
                    : 'Follow',
                style: TextStyle(
                  color: user.isFollowing ? Colors.grey[700] : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitial() {
    return Center(
      child: Text(
        user.displayName.isNotEmpty
            ? user.displayName[0].toUpperCase()
            : user.username[0].toUpperCase(),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Find Friends',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // Search field
                TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Search by username or name',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _controller.clear();
                              context.read<SocialProvider>().clearSearch();
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
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
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.searchQuery.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Search for friends',
                          style: TextStyle(color: Colors.grey[600]),
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
                        Icon(Icons.person_off, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No users found',
                          style: TextStyle(color: Colors.grey[600]),
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
    );
  }
}
