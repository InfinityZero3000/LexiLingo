import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';

class LearningStreakStatsPage extends StatelessWidget {
  const LearningStreakStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _StatsPageScaffold(
      title: 'profile.streakDetails',
      builder: (context, profileProvider, progressProvider) {
        final stats = profileProvider.stats;
        final summary = progressProvider.summary;
        final currentStreak =
            stats?.currentStreak ?? summary?.currentStreak ?? 0;
        final longestStreak = summary?.longestStreak ?? 0;

        return _singleCard(
          context,
          children: [
            _detailRow(
              'profile.currentStreak'.tr(),
              'profile.daysCount'.tr(namedArgs: {'count': '$currentStreak'}),
            ),
            const Divider(height: 20),
            _detailRow(
              'profile.longestStreak'.tr(),
              'profile.daysCount'.tr(namedArgs: {'count': '$longestStreak'}),
            ),
            const SizedBox(height: 10),
            Text(
              currentStreak > 0
                  ? 'profile.keepLearningDaily'.tr()
                  : 'profile.startLessonToday'.tr(),
              style: TextStyle(color: AppColorRoles.textMuted(isDark)),
            ),
          ],
        );
      },
    );
  }
}

class LearningLessonsStatsPage extends StatelessWidget {
  const LearningLessonsStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _StatsPageScaffold(
      title: 'profile.lessonsDetails',
      builder: (context, profileProvider, progressProvider) {
        final stats = profileProvider.stats;
        final summary = progressProvider.summary;
        final lessonsCompleted =
            stats?.totalLessonsCompleted ?? summary?.lessonsCompleted ?? 0;
        final weeklyLessons = profileProvider.weeklyActivity.fold<int>(
          0,
          (sum, item) => sum + item.lessonsCompleted,
        );

        return _singleCard(
          context,
          children: [
            _detailRow(
              'profile.totalLessonsCompleted'.tr(),
              '$lessonsCompleted',
            ),
            const Divider(height: 20),
            _detailRow(
              'profile.lessonsCompletedThisWeek'.tr(),
              '$weeklyLessons',
            ),
          ],
        );
      },
    );
  }
}

class LearningCoursesStatsPage extends StatelessWidget {
  const LearningCoursesStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _StatsPageScaffold(
      title: 'profile.coursesDetails',
      builder: (context, profileProvider, progressProvider) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final stats = profileProvider.stats;
        final summary = progressProvider.summary;
        final coursesCompleted =
            stats?.totalCoursesCompleted ?? summary?.coursesCompleted ?? 0;
        final courseProgressList = progressProvider.courseProgressList;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _singleCard(
              context,
              children: [
                _detailRow(
                  'profile.totalCoursesFinished'.tr(),
                  '$coursesCompleted',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (courseProgressList.isEmpty)
              _singleCard(
                context,
                children: [
                  Text(
                    'profile.noEnrolledCoursesYet'.tr(),
                    style: TextStyle(color: AppColorRoles.textMuted(isDark)),
                  ),
                ],
              )
            else
              ...courseProgressList.map(
                (course) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _courseProgressCard(context, course),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _courseProgressCard(
    BuildContext context,
    CourseProgressDetail course,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    final progress = course.progressPercentage;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CourseDetailScreen(courseId: course.courseId),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkMuted : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppColors.borderDarkSoft : AppColors.grey300,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    course.courseTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppColorRoles.textMuted(isDark),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (progress / 100).clamp(0.0, 1.0),
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: AppColors.grey300,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
            const SizedBox(height: 6),
            Text(
              'profile.courseProgressSummary'.tr(
                namedArgs: {
                  'percent': progress.toStringAsFixed(0),
                  'completed': '${course.lessonsCompleted}',
                  'total': '${course.totalLessons}',
                },
              ),
              style: TextStyle(
                color: AppColorRoles.textMuted(isDark),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LearningVocabularyStatsPage extends StatelessWidget {
  const LearningVocabularyStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _StatsPageScaffold(
      title: 'profile.vocabularyDetails',
      builder: (context, profileProvider, progressProvider) {
        final stats = profileProvider.stats;
        final vocabularyMastered = stats?.totalVocabularyMastered ?? 0;
        final weeklyVocabulary = profileProvider.weeklyActivity.fold<int>(
          0,
          (sum, item) => sum + item.vocabularyLearned,
        );

        return _singleCard(
          context,
          children: [
            _detailRow(
              'profile.totalVocabularyMastered'.tr(),
              '$vocabularyMastered',
            ),
            const Divider(height: 20),
            _detailRow('profile.newWordsThisWeek'.tr(), '$weeklyVocabulary'),
          ],
        );
      },
    );
  }
}

class LearningTestsStatsPage extends StatelessWidget {
  const LearningTestsStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _StatsPageScaffold(
      title: 'profile.testsDetails',
      builder: (context, profileProvider, progressProvider) {
        final stats = profileProvider.stats;
        final testsPassed = stats?.totalTestsPassed ?? 0;
        final averageScore = stats?.averageTestScore ?? 0.0;

        return _singleCard(
          context,
          children: [
            _detailRow('profile.totalTestsPassed'.tr(), '$testsPassed'),
            const Divider(height: 20),
            _detailRow(
              'profile.averageScore'.tr(),
              averageScore > 0
                  ? '${averageScore.toStringAsFixed(1)}%'
                  : 'profile.noScoreYet'.tr(),
            ),
          ],
        );
      },
    );
  }
}

class _StatsPageScaffold extends StatefulWidget {
  final String title;
  final Widget Function(
    BuildContext context,
    ProfileProvider profileProvider,
    ProgressProvider progressProvider,
  )
  builder;

  const _StatsPageScaffold({required this.title, required this.builder});

  @override
  State<_StatsPageScaffold> createState() => _StatsPageScaffoldState();
}

class _StatsPageScaffoldState extends State<_StatsPageScaffold> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profileProvider = context.read<ProfileProvider>();
      final progressProvider = context.read<ProgressProvider>();

      if (!profileProvider.hasStats && !profileProvider.isLoadingStats) {
        profileProvider.loadProfileData();
      }
      if (progressProvider.summary == null && !progressProvider.isLoading) {
        progressProvider.fetchMyProgress();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title.tr())),
      body: Consumer2<ProfileProvider, ProgressProvider>(
        builder: (context, profileProvider, progressProvider, _) {
          final isLoading =
              (profileProvider.isLoadingStats && profileProvider.stats == null) ||
              (progressProvider.isLoading && progressProvider.summary == null);

          if (isLoading) {
            return const Center(child: LottieLoadingWidget.medium());
          }

          return RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                profileProvider.loadProfileData(),
                progressProvider.fetchMyProgress(),
              ]);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: widget.builder(context, profileProvider, progressProvider),
            ),
          );
        },
      ),
    );
  }
}

Widget _singleCard(BuildContext context, {required List<Widget> children}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark ? AppColors.surfaceDarkMuted : AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isDark ? AppColors.borderDarkSoft : AppColors.grey300,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

Widget _detailRow(String label, String value) {
  return Row(
    children: [
      Expanded(
        child: Builder(
          builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: AppColorRoles.textMuted(isDark),
              ),
            );
          },
        ),
      ),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ],
  );
}
