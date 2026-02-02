import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/core/widgets/glassmorphic_components.dart' as glass;
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/pages/vocab_library_page.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/daily_review_card.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/streak_widget.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/daily_challenges_widget.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';
import 'package:lexilingo_app/features/notifications/presentation/pages/notifications_page.dart';
import 'package:lexilingo_app/features/gamification/gamification.dart';

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
                    // Bento Stats Grid
                    _buildBentoStatsGrid(context, homeProvider, authProvider),
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
                    // Enrolled courses section - always show if user is authenticated
                    _buildSectionTitle(context, 'Continue Learning'),
                    const SizedBox(height: 12),
                    _buildEnrolledCoursesSection(context, homeProvider),
                    const SizedBox(height: 24),
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
    
    return Consumer<NotificationProvider>(
      builder: (context, notificationProvider, child) {
        return PersonalizedGreetingHeader(
          userName: displayName,
          totalXP: totalXP,
          avatarUrl: user?.avatarUrl,
          notificationCount: notificationProvider.unreadCount,
          onNotificationTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            );
          },
          onAvatarTap: () {
            // Navigate to profile or settings
          },
        );
      },
    );
  }

  /// Bento Grid Stats - Modern dashboard layout
  Widget _buildBentoStatsGrid(
    BuildContext context,
    HomeProvider homeProvider,
    AuthProvider authProvider,
  ) {
    return Consumer3<StreakProvider, LevelProvider, GamificationProvider>(
      builder: (context, streakProvider, levelProvider, gamificationProvider, _) {
        final streak = streakProvider.streak?.currentStreak ?? homeProvider.streakDays;
        final xp = levelProvider.levelStatus.totalXP;
        final gems = gamificationProvider.wallet?.gems ?? 0;
        final lessonsToday = homeProvider.dailyXP ~/ 10; // Approximate lessons from XP
        final progress = levelProvider.levelStatus.progressPercentage;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              // Row 1: Streak + XP
              Row(
                children: [
                  // Streak Card - Large
                  Expanded(
                    flex: 3,
                    child: _buildBentoCard(
                      context,
                      icon: Icons.local_fire_department,
                      iconColor: Colors.orange,
                      bgGradient: const [Color(0xFFFEF3C7), Color(0xFFFED7AA)],
                      title: 'Streak',
                      value: '$streak',
                      subtitle: 'days',
                      height: 120,
                      onTap: () {
                        if (streakProvider.streak != null) {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => StreakDetailsSheet(streak: streakProvider.streak!),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // XP Card
                  Expanded(
                    flex: 2,
                    child: _buildBentoCard(
                      context,
                      icon: Icons.star,
                      iconColor: const Color(0xFFF59E0B),
                      bgGradient: const [Color(0xFFFEF9C3), Color(0xFFFDE68A)],
                      title: 'XP',
                      value: LevelCalculator.formatXP(xp),
                      subtitle: 'earned',
                      height: 120,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Row 2: Gems + Progress + Lessons
              Row(
                children: [
                  // Gems Card
                  Expanded(
                    child: _buildBentoCard(
                      context,
                      icon: Icons.diamond,
                      iconColor: const Color(0xFF8B5CF6),
                      bgGradient: const [Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
                      title: 'Gems',
                      value: '$gems',
                      subtitle: null,
                      height: 100,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WalletScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Progress Card with Ring
                  Expanded(
                    child: Container(
                      height: 100,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFDBEAFE), Color(0xFFBFDBFE)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        glass.AnimatedProgressRing(
                            progress: progress / 100,
                            size: 50,
                            strokeWidth: 5,
                            gradientColors: const [Color(0xFF3B82F6), Color(0xFF6366F1)],
                            child: Text(
                              '${progress.toInt()}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Level Progress',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF3B82F6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Lessons Today Card
                  Expanded(
                    child: _buildBentoCard(
                      context,
                      icon: Icons.menu_book,
                      iconColor: const Color(0xFF10B981),
                      bgGradient: const [Color(0xFFD1FAE5), Color(0xFFA7F3D0)],
                      title: 'Today',
                      value: '$lessonsToday',
                      subtitle: 'lessons',
                      height: 100,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBentoCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required List<Color> bgGradient,
    required String title,
    required String value,
    String? subtitle,
    required double height,
    VoidCallback? onTap,
  }) {
    // Adjust padding and sizes based on card height
    final isSmallCard = height <= 100;
    final padding = isSmallCard ? 10.0 : 14.0;
    final iconPadding = isSmallCard ? 6.0 : 8.0;
    final iconSize = isSmallCard ? 14.0 : 18.0;
    final valueFontSize = isSmallCard ? 18.0 : 22.0;
    final labelFontSize = isSmallCard ? 10.0 : 11.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: bgGradient,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: iconColor.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: EdgeInsets.all(iconPadding),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: iconSize),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.bold,
                      color: iconColor.withValues(alpha: 0.9),
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: labelFontSize,
                        color: iconColor.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: labelFontSize,
                        color: iconColor.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakCard(BuildContext context, HomeProvider provider) {
    return Consumer<StreakProvider>(
      builder: (context, streakProvider, child) {
        final streak = streakProvider.streak;
        final currentStreak = streak?.currentStreak ?? provider.streakDays;
        final longestStreak = streak?.longestStreak ?? 0;
        final isActiveToday = streak?.isActiveToday ?? false;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: AnimatedStreakCard(
            streakDays: currentStreak,
            longestStreak: longestStreak,
            isActiveToday: isActiveToday,
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
          ),
        );
      },
    );
  }

  Widget _buildDailyGoalCard(BuildContext context, HomeProvider provider) {
    final percentage = provider.dailyProgressPercentage;
    final isCompleted = percentage >= 1.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isCompleted
              ? [const Color(0xFFD1FAE5), const Color(0xFFA7F3D0)]
              : [const Color(0xFFDBEAFE), const Color(0xFFBFDBFE)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isCompleted ? Colors.green : Colors.blue).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Animated Progress Ring
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            child: glass.AnimatedProgressRing(
              progress: percentage.clamp(0.0, 1.0),
              size: 70,
              strokeWidth: 6,
              gradientColors: isCompleted
                  ? const [Color(0xFF10B981), Color(0xFF059669)]
                  : const [Color(0xFF3B82F6), Color(0xFF6366F1)],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCompleted)
                    const Icon(Icons.check, color: Color(0xFF10B981), size: 20)
                  else
                    Text(
                      '${(percentage * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isCompleted ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isCompleted ? Icons.emoji_events : Icons.bolt,
                        color: isCompleted ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Daily XP Goal',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isCompleted ? const Color(0xFF065F46) : const Color(0xFF1E40AF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${provider.dailyXP}/${provider.dailyGoalXP} XP',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCompleted ? Icons.celebration : Icons.trending_up,
                        size: 14,
                        color: isCompleted ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCompleted ? 'Goal completed!' : 'Keep going!',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isCompleted ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnrolledCoursesSection(BuildContext context, HomeProvider provider) {
    // Show loading state if courses are being loaded
    if (provider.isLoading && provider.enrolledCourses.isEmpty) {
      return SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 2,
          itemBuilder: (context, index) {
            return const CardSkeleton(isHorizontal: true);
          },
        ),
      );
    }

    // Show empty state if no enrolled courses
    if (provider.enrolledCourses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              Icon(
                Icons.school_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No enrolled courses yet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start your learning journey by enrolling in a course',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Show enrolled courses
    return _buildEnrolledCourses(context, provider);
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
          // Staggered animation for enrolled courses
          return AnimatedListItem(
            index: index,
            duration: const Duration(milliseconds: 300),
            delayPerItem: const Duration(milliseconds: 80),
            child: _buildEnrolledCourseCard(context, course),
          );
        },
      ),
    );
  }

  Widget _buildEnrolledCourseCard(BuildContext context, CourseEntity course) {
    final progress = course.userProgress ?? 0;
    final progressColor = progress >= 80 
        ? const Color(0xFF10B981) 
        : progress >= 50 
            ? const Color(0xFFF59E0B) 
            : const Color(0xFF3B82F6);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CourseDetailScreen(courseId: course.id),
          ),
        );
      },
      child: Container(
        width: 320,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              progressColor.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: progressColor.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: progressColor.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Course thumbnail
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: progressColor.withValues(alpha: 0.1),
                  image: course.thumbnailUrl != null
                      ? DecorationImage(
                          image: NetworkImage(course.thumbnailUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: progressColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: course.thumbnailUrl == null
                    ? Icon(Icons.school, size: 32, color: progressColor)
                    : null,
              ),
              const SizedBox(width: 16),
              // Info section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: progressColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            course.level,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: progressColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${course.totalLessons} lessons',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Progress bar
                    Stack(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: progressColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress / 100,
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [progressColor, progressColor.withValues(alpha: 0.7)],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${progress.toInt()}% complete',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: progressColor,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [progressColor, progressColor.withValues(alpha: 0.8)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow, size: 14, color: Colors.white),
                              SizedBox(width: 2),
                              Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedCourses(BuildContext context, HomeProvider provider) {
    // Show skeleton loading while courses are loading
    if (provider.isLoading && provider.featuredCourses.isEmpty) {
      return SizedBox(
        height: 320,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 3,
          itemBuilder: (context, index) {
            return Container(
              width: 280,
              margin: const EdgeInsets.only(right: 16),
              child: const CardSkeleton(isHorizontal: false),
            );
          },
        ),
      );
    }

    return SizedBox(
      height: 320,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: provider.featuredCourses.length,
        itemBuilder: (context, index) {
          final course = provider.featuredCourses[index];
          // Staggered animation for featured courses
          return AnimatedListItem(
            index: index,
            duration: const Duration(milliseconds: 350),
            delayPerItem: const Duration(milliseconds: 100),
            child: _buildCourseCard(context, course, provider),
          );
        },
      ),
    );
  }

  Widget _buildCourseCard(
    BuildContext context,
    CourseEntity course,
    HomeProvider provider,
  ) {
    final levelColor = _getLevelColor(course.level);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CourseDetailScreen(
              courseId: course.id,
              heroTag: 'featured-course-image-${course.id}',
            ),
          ),
        );
      },
      child: Container(
        width: 280,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                : [Colors.white, const Color(0xFFF8FAFC)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.1)
                : levelColor.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: levelColor.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero animation for course thumbnail
            Hero(
              tag: 'featured-course-image-${course.id}',
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  color: levelColor.withValues(alpha: 0.1),
                  image: course.thumbnailUrl != null
                      ? DecorationImage(
                          image: NetworkImage(course.thumbnailUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: Stack(
                  children: [
                    // Gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),
                    if (course.thumbnailUrl == null)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: Icon(Icons.school_rounded, size: 40, color: Colors.white.withValues(alpha: 0.9)),
                        ),
                      ),
                    // Level badge - top left
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [levelColor, levelColor.withValues(alpha: 0.85)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: levelColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          course.level,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    // XP badge - top right
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              '${course.totalXp} XP',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Course title overlay at bottom
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Text(
                        course.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom section with info and action
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Info chips row
                    Row(
                      children: [
                        _buildInfoChip(
                          icon: Icons.menu_book_rounded,
                          label: '${course.totalLessons} lessons',
                          color: const Color(0xFF3B82F6),
                        ),
                        const SizedBox(width: 8),
                        _buildInfoChip(
                          icon: Icons.translate_rounded,
                          label: course.language,
                          color: const Color(0xFF8B5CF6),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Action button
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [levelColor, levelColor.withValues(alpha: 0.85)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: levelColor.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_circle_filled_rounded, size: 20, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Start Learning',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'beginner':
        return const Color(0xFF10B981);
      case 'elementary':
        return const Color(0xFF34D399);
      case 'intermediate':
        return const Color(0xFFF59E0B);
      case 'upper-intermediate':
        return const Color(0xFFF97316);
      case 'advanced':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  context,
                  icon: Icons.smart_toy,
                  title: 'AI Tutor',
                  subtitle: 'Practice speaking',
                  color: AppColors.primary,
                  bgColor: AppColors.primary.withValues(alpha: 0.1),
                  onTap: () {
                    // Navigate to AI Chat - handled by bottom nav
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildQuickActionCard(
                  context,
                  icon: Icons.style,
                  title: 'Vocabulary',
                  subtitle: 'Review flashcards',
                  color: Colors.orange,
                  bgColor: const Color(0xFFFFF7ED),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const VocabLibraryPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  context,
                  icon: Icons.store,
                  title: 'Shop',
                  subtitle: 'Spend your gems',
                  color: const Color(0xFFF59E0B),
                  bgColor: const Color(0xFFFEF3C7),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ShopScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildQuickActionCard(
                  context,
                  icon: Icons.leaderboard,
                  title: 'Leaderboard',
                  subtitle: 'Compete globally',
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFD1FAE5),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textGrey,
                fontSize: 11,
              ),
            ),
          ],
        ),
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
