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
    return _StatsPageScaffold(
      title: 'Streak Details',
      builder: (context, profileProvider, progressProvider) {
        final stats = profileProvider.stats;
        final summary = progressProvider.summary;
        final currentStreak =
            stats?.currentStreak ?? summary?.currentStreak ?? 0;
        final longestStreak = summary?.longestStreak ?? 0;

        return _singleCard(
          context,
          children: [
            _detailRow('Current streak', '$currentStreak days'),
            const Divider(height: 20),
            _detailRow('Longest streak', '$longestStreak days'),
            const SizedBox(height: 10),
            Text(
              currentStreak > 0
                  ? 'Keep learning daily to maintain your streak.'
                  : 'Start one lesson today to build your streak.',
              style: const TextStyle(color: AppColors.textGrey),
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
      title: 'Lessons Details',
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
            _detailRow('Total lessons completed', '$lessonsCompleted'),
            const Divider(height: 20),
            _detailRow('Lessons completed this week', '$weeklyLessons'),
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
      title: 'Courses Details',
      builder: (context, profileProvider, progressProvider) {
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
                _detailRow('Total courses finished', '$coursesCompleted'),
              ],
            ),
            const SizedBox(height: 12),
            if (courseProgressList.isEmpty)
              _singleCard(
                context,
                children: const [
                  Text(
                    'No enrolled courses yet.',
                    style: TextStyle(color: AppColors.textGrey),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.grey300),
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
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppColors.textGrey,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (progress / 100).clamp(0.0, 1.0),
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: AppColors.grey300,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${progress.toStringAsFixed(0)}% • ${course.lessonsCompleted}/${course.totalLessons} lessons',
              style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
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
      title: 'Vocabulary Details',
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
            _detailRow('Total vocabulary mastered', '$vocabularyMastered'),
            const Divider(height: 20),
            _detailRow('New words this week', '$weeklyVocabulary'),
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
      title: 'Tests Details',
      builder: (context, profileProvider, progressProvider) {
        final stats = profileProvider.stats;
        final testsPassed = stats?.totalTestsPassed ?? 0;
        final averageScore = stats?.averageTestScore ?? 0.0;

        return _singleCard(
          context,
          children: [
            _detailRow('Total tests passed', '$testsPassed'),
            const Divider(height: 20),
            _detailRow(
              'Average score',
              averageScore > 0
                  ? '${averageScore.toStringAsFixed(1)}%'
                  : 'No score yet',
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
      appBar: AppBar(title: Text(widget.title)),
      body: Consumer2<ProfileProvider, ProgressProvider>(
        builder: (context, profileProvider, progressProvider, _) {
          final isLoading =
              (profileProvider.isLoadingStats || progressProvider.isLoading) &&
              profileProvider.stats == null &&
              progressProvider.summary == null;

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
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.grey300),
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
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.textGrey),
        ),
      ),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ],
  );
}
