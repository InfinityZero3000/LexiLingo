import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/progress_card.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/course_progress_card.dart';

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
      appBar: AppBar(
        title: const Text('My Progress'),
        centerTitle: true,
      ),
      body: Consumer<ProgressProvider>(
        builder: (context, progressProvider, child) {
          if (progressProvider.isLoading) {
            return const LoadingScreen(message: 'Loading progress...');
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
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final summary = progressProvider.summary;
          final courseProgressList = progressProvider.courseProgressList;

          if (summary == null) {
            return const Center(
              child: Text('No progress data available'),
            );
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
                    title: 'Overall Statistics',
                    icon: Icons.analytics,
                    children: [
                      _buildStatRow(
                        context,
                        'Total XP',
                        summary.totalXp.toString(),
                        Icons.star,
                      ),
                      const Divider(),
                      _buildStatRow(
                        context,
                        'Courses Enrolled',
                        summary.coursesEnrolled.toString(),
                        Icons.school,
                      ),
                      const Divider(),
                      _buildStatRow(
                        context,
                        'Courses Completed',
                        summary.coursesCompleted.toString(),
                        Icons.check_circle,
                      ),
                      const Divider(),
                      _buildStatRow(
                        context,
                        'Lessons Completed',
                        summary.lessonsCompleted.toString(),
                        Icons.done_all,
                      ),
                      const Divider(),
                      _buildStatRow(
                        context,
                        'Current Streak',
                        '${summary.currentStreak} days',
                        Icons.local_fire_department,
                      ),
                      const Divider(),
                      _buildStatRow(
                        context,
                        'Longest Streak',
                        '${summary.longestStreak} days',
                        Icons.military_tech,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Course Progress
                  Text(
                    'Course Progress',
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No courses enrolled yet',
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
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
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
