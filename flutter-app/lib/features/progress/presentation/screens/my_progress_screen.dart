import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/progress_card.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/course_progress_card.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/xp_line_chart.dart';

/// My Progress Screen
/// Displays user's overall progress statistics
class MyProgressScreen extends StatefulWidget {
  const MyProgressScreen({super.key});

  @override
  State<MyProgressScreen> createState() => _MyProgressScreenState();
}

class _MyProgressScreenState extends State<MyProgressScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProgressProvider>().fetchMyProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('progress.title'.tr()), centerTitle: true),
      body: Consumer<ProgressProvider>(
        builder: (context, progressProvider, child) {
          if (progressProvider.isLoading) {
            return LoadingScreen(message: 'progress.loadingProgress'.tr());
          }

          if (progressProvider.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    progressProvider.errorMessage!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      progressProvider.fetchMyProgress();
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text('common.retry'.tr()),
                  ),
                ],
              ),
            );
          }

          final summary = progressProvider.summary;
          final courseProgressList = progressProvider.courseProgressList;

          if (summary == null) {
            return Center(child: Text('progress.noProgressDataAvailable'.tr()));
          }

          return RefreshIndicator(
            onRefresh: () => progressProvider.fetchMyProgress(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overall Stats
                  ProgressCard(
                    title: 'progress.overallStatistics'.tr(),
                    icon: Icons.analytics,
                    children: [
                      _buildStatRow(
                        context,
                        'profile.totalXp'.tr(),
                        summary.totalXp.toString(),
                        Icons.star,
                      ),
                      const Divider(),
                      _buildStatRow(
                        context,
                        'progress.coursesEnrolledStat'.tr(),
                        summary.coursesEnrolled.toString(),
                        Icons.school,
                      ),
                      const Divider(),
                      _buildStatRow(
                        context,
                        'progress.coursesCompletedStat'.tr(),
                        summary.coursesCompleted.toString(),
                        Icons.check_circle,
                      ),
                      const Divider(),
                      _buildStatRow(
                        context,
                        'progress.lessonsCompletedStat'.tr(),
                        summary.lessonsCompleted.toString(),
                        Icons.done_all,
                      ),
                      const Divider(),
                      _buildStatRow(
                        context,
                        'profile.currentStreak'.tr(),
                        'profile.daysCount'.tr(
                          namedArgs: {'count': '${summary.currentStreak}'},
                        ),
                        Icons.local_fire_department,
                      ),
                      const Divider(),
                      _buildStatRow(
                        context,
                        'profile.longestStreak'.tr(),
                        'profile.daysCount'.tr(
                          namedArgs: {'count': '${summary.longestStreak}'},
                        ),
                        Icons.military_tech,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Weekly Overview Charts
                  _WeeklyOverviewSection(),

                  const SizedBox(height: 24),

                  // Course Progress
                  Text(
                    'progress.courseProgressTitle'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (courseProgressList.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.inbox,
                                size: 48,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'profile.noEnrolledCoursesYet'.tr(),
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ...courseProgressList.map((courseProgress) {
                      return CourseProgressCard(
                        courseProgress: courseProgress,
                        onTap: () {
                          // Navigate to course detail
                          Navigator.pushNamed(
                            context,
                            '/course-detail',
                            arguments: courseProgress.courseId,
                          );
                        },
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Weekly overview section showing XP trend and lessons bar chart.
class _WeeklyOverviewSection extends StatefulWidget {
  const _WeeklyOverviewSection();

  @override
  State<_WeeklyOverviewSection> createState() => _WeeklyOverviewSectionState();
}

class _WeeklyOverviewSectionState extends State<_WeeklyOverviewSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppColorRoles.primary(isDark);

    return Consumer<HomeProvider>(
      builder: (context, homeProvider, _) {
        final weekly = homeProvider.weeklyProgress;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly Overview',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${weekly.totalXP} XP · ${weekly.totalLessons} lessons · ${weekly.daysActive}/7 days active',
              style: TextStyle(
                fontSize: 13,
                color: AppColorRoles.textMuted(isDark),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceDarkMuted
                    : AppColors.grey100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AppColorRoles.textMuted(isDark),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'XP'),
                  Tab(text: 'Lessons'),
                  Tab(text: 'Activity'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: TabBarView(
                controller: _tabController,
                children: [
                  XpLineChart(weeklyProgress: weekly),
                  LessonsBarChart(weeklyProgress: weekly),
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: WeekActivityHeatmap(weeklyProgress: weekly),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
