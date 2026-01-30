import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/pages/vocab_library_page.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/daily_review_card.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/streak_widget.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/daily_challenges_widget.dart';
import 'package:lexilingo_app/features/level/level.dart';

/// Helper function to get icon from streak identifier
IconData _getStreakIconData(String identifier) {
  switch (identifier) {
    case 'trophy':
      return Icons.emoji_events;
    case 'fire':
      return Icons.local_fire_department;
    case 'bolt':
      return Icons.bolt;
    case 'star':
      return Icons.star;
    case 'sparkles':
      return Icons.auto_awesome;
    default:
      return Icons.local_fire_department;
  }
}

class HomePageNew extends StatefulWidget {
  const HomePageNew({super.key});

  @override
  State<HomePageNew> createState() => _HomePageNewState();
}

class _HomePageNewState extends State<HomePageNew> {
  @override
  void initState() {
    super.initState();
    // Load home data after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final homeProvider = context.read<HomeProvider>();
      final authProvider = context.read<AuthProvider>();
      homeProvider.loadHomeData().then((_) {
        // Sync XP to LevelProvider from AuthProvider (real user data)
        final levelProvider = context.read<LevelProvider>();
        final userXP = authProvider.currentUser?.xp ?? 0;
        levelProvider.updateLevel(userXP);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer3<HomeProvider, UserProvider, AuthProvider>(
          builder: (context, homeProvider, userProvider, authProvider, child) {
            if (homeProvider.isLoading &&
                homeProvider.featuredCourses.isEmpty) {
              return _buildSkeletonLoading();
            }

            if (homeProvider.errorMessage != null) {
              return ErrorDisplayWidget.fromMessage(
                message: homeProvider.errorMessage!,
                onRetry: () => homeProvider.loadHomeData(),
              );
            }

            return RefreshIndicator(
              onRefresh: () => homeProvider.refreshData(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, homeProvider, authProvider),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: LevelProgressCard(),
                    ),
                    const SizedBox(height: 16),
                    _buildStreakCard(context, homeProvider),
                    const SizedBox(height: 24),
                    _buildDailyGoalCard(context, homeProvider),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: DailyChallengesCard(),
                    ),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: DailyReviewCard(),
                    ),
                    const SizedBox(height: 24),
                    if (homeProvider.enrolledCourses.isNotEmpty) ...[
                      _buildSectionTitle(context, 'Continue Learning'),
                      const SizedBox(height: 12),
                      _buildEnrolledCourses(context, homeProvider),
                      const SizedBox(height: 24),
                    ],
                    _buildSectionTitle(context, 'Featured Courses'),
                    const SizedBox(height: 12),
                    _buildFeaturedCourses(context, homeProvider),
                    const SizedBox(height: 24),
                    _buildSectionTitle(context, 'Quick Actions'),
                    const SizedBox(height: 12),
                    _buildQuickActions(context),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    HomeProvider homeProvider,
    AuthProvider authProvider,
  ) {
    // Get user display name from AuthProvider
    final user = authProvider.currentUser;
    final displayName = user?.displayName.isNotEmpty == true 
        ? user!.displayName 
        : user?.username ?? 'User';
    final totalXP = user?.xp ?? homeProvider.totalXP;
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.2),
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: user?.avatarUrl != null
                ? ClipOval(
                    child: Image.network(
                      user!.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.person, color: AppColors.primary),
                    ),
                  )
                : const Icon(Icons.person, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, $displayName!',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$totalXP XP earned',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textGrey),
                ),
                Text(
                  'Ready to learn?',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakCard(BuildContext context, HomeProvider provider) {
    return Consumer<StreakProvider>(
      builder: (context, streakProvider, child) {
        final streak = streakProvider.streak;
        final currentStreak = streak?.currentStreak ?? provider.streakDays;
        final isActiveToday = streak?.isActiveToday ?? false;
        final streakAtRisk = streak?.streakAtRisk ?? false;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: GestureDetector(
            onTap: () {
              if (streak != null) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => StreakDetailsSheet(streak: streak),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: streakAtRisk
                      ? [const Color(0xFFFEF3C7), const Color(0xFFFED7AA)]
                      : [const Color(0xFFfef9c3), const Color(0xFFdcfce7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: streakAtRisk
                      ? Colors.orange.shade200
                      : Colors.green.shade100,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'DAILY MOMENTUM',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: streakAtRisk
                                            ? Colors.orange.shade800
                                            : Colors.green.shade800,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.5,
                                      ),
                                ),
                                if (streakAtRisk) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'AT RISK',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$currentStreak Day Streak',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: AppColors.textDark,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1,
                                  ),
                            ),
                            if (isActiveToday) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green.shade600,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Done for today!',
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: currentStreak > 0
                                  ? const Color(0xFFFACC15)
                                  : Colors.grey.shade400,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              streak != null
                                  ? _getStreakIconData(streak.streakIcon)
                                  : Icons.local_fire_department,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          if (streak != null && streak.longestStreak > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.emoji_events,
                                  size: 11,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${streak.longestStreak}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        7,
                        (index) => _buildDayItem(
                          ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                          index < provider.weekProgress.length &&
                              provider.weekProgress[index],
                          isCurrent: index == 3,
                          isFuture: index > 3,
                        ),
                      ),
                    ),
                  ),
                  // Freeze info
                  if (streak != null && streak.freezeCount > 0) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.ac_unit, size: 14, color: Colors.cyan),
                        const SizedBox(width: 4),
                        Text(
                          '${streak.freezeCount} streak freeze${streak.freezeCount > 1 ? 's' : ''} available',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDailyGoalCard(BuildContext context, HomeProvider provider) {
    final percentage = provider.dailyProgressPercentage;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Daily XP Goal',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '${provider.dailyXP}/${provider.dailyGoalXP} XP',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: percentage.clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(
            '${(percentage * 100).toInt()}% complete',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildEnrolledCourses(BuildContext context, HomeProvider provider) {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: provider.enrolledCourses.length,
        itemBuilder: (context, index) {
          final course = provider.enrolledCourses[index];
          return _buildEnrolledCourseCard(context, course);
        },
      ),
    );
  }

  Widget _buildEnrolledCourseCard(BuildContext context, CourseEntity course) {
    return Container(
      width: 320,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${course.totalLessons} lessons • ${course.level}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    // Navigate to course detail
                  },
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Continue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade200,
                image: course.thumbnailUrl != null
                    ? DecorationImage(
                        image: NetworkImage(course.thumbnailUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: course.thumbnailUrl == null
                  ? const Icon(Icons.image, size: 48, color: Colors.grey)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedCourses(BuildContext context, HomeProvider provider) {
    return SizedBox(
      height: 280,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: provider.featuredCourses.length,
        itemBuilder: (context, index) {
          final course = provider.featuredCourses[index];
          return _buildCourseCard(context, course, provider);
        },
      ),
    );
  }

  Widget _buildCourseCard(
    BuildContext context,
    CourseEntity course,
    HomeProvider provider,
  ) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              color: Colors.grey.shade200,
              image: course.thumbnailUrl != null
                  ? DecorationImage(
                      image: NetworkImage(course.thumbnailUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Stack(
              children: [
                if (course.thumbnailUrl == null)
                  const Center(
                    child: Icon(Icons.school, size: 48, color: Colors.grey),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      course.level,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            '4.5', // TODO: Add rating field to CourseEntity
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.people,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${course.totalLessons}', // Show lessons count as placeholder
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        // TODO: Implement course enrollment
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Course enrollment coming soon!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('Enroll'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                // Navigate to AI Chat
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.smart_toy, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AI Tutor',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Practice speaking',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textGrey,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const VocabLibraryPage(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.style, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Vocabulary',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Review flashcards',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textGrey,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
    );
  }

  Widget _buildDayItem(
    String day,
    bool completed, {
    bool isCurrent = false,
    bool isFuture = false,
  }) {
    return Column(
      children: [
        Text(
          day,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isCurrent ? AppColors.primary : Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        if (completed)
          const Icon(Icons.check_circle, color: Colors.green, size: 20)
        else if (isCurrent)
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            padding: const EdgeInsets.all(6),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          )
        else
          Icon(
            Icons.circle,
            color: Colors.grey.withValues(alpha: 0.4),
            size: 20,
          ),
      ],
    );
  }

  /// Build skeleton loading state for home page
  Widget _buildSkeletonLoading() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header skeleton
          ShimmerContainer(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const SkeletonCircle(size: 48),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonText(width: 150, height: 14),
                      SizedBox(height: 6),
                      SkeletonText(width: 100, height: 12),
                      SizedBox(height: 6),
                      SkeletonText(width: 120, height: 18),
                    ],
                  ),
                  const Spacer(),
                  const SkeletonCircle(size: 40),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Streak card skeleton
          const SkeletonProgressStats(),
          const SizedBox(height: 24),
          // Daily goal skeleton
          ShimmerContainer(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Section title skeleton
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: ShimmerContainer(
              child: SkeletonText(width: 150, height: 20),
            ),
          ),
          const SizedBox(height: 12),
          // Courses skeleton
          const SkeletonHomeSection(),
          const SizedBox(height: 24),
          // Another section
          const SkeletonHomeSection(),
        ],
      ),
    );
  }
}
