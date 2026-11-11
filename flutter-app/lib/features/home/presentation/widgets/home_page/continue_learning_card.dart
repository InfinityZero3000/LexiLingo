import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_list_screen.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

/// Shows the learner's active course first, then rotates to a short learning
/// reminder. A course at 0% is a start prompt, never "Continue learning".
class ContinueLearningCard extends StatelessWidget {
  const ContinueLearningCard({
    super.key,
    this.rotationInterval = const Duration(seconds: 6),
  });

  final Duration rotationInterval;

  static CourseEntity? pick(List<CourseEntity> enrolled) {
    for (final course in enrolled) {
      final progress = course.userProgress ?? 0;
      if (progress > 0 && progress < 100) return course;
    }
    return null;
  }

  static CourseEntity? pickUnstarted(List<CourseEntity> enrolled) {
    for (final course in enrolled) {
      if ((course.userProgress ?? 0) <= 0) return course;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();
    if (provider.isLoadingEnrolled && provider.enrolledCourses.isEmpty) {
      return const SizedBox.shrink();
    }

    final activeCourse = pick(provider.enrolledCourses);
    final unstartedCourse = pickUnstarted(provider.enrolledCourses);

    return _RotatingLearningCard(
      key: ValueKey(
        activeCourse == null
            ? 'prompt:${unstartedCourse?.id ?? 'discover'}'
            : 'active:${activeCourse.id}',
      ),
      activeCourse: activeCourse,
      unstartedCourse: unstartedCourse,
      rotationInterval: rotationInterval,
    );
  }
}

class _RotatingLearningCard extends StatefulWidget {
  const _RotatingLearningCard({
    super.key,
    required this.activeCourse,
    required this.unstartedCourse,
    required this.rotationInterval,
  });

  final CourseEntity? activeCourse;
  final CourseEntity? unstartedCourse;
  final Duration rotationInterval;

  @override
  State<_RotatingLearningCard> createState() => _RotatingLearningCardState();
}

class _RotatingLearningCardState extends State<_RotatingLearningCard> {
  Timer? _rotationTimer;
  late bool _showReminder;
  bool _tickerEnabled = false;

  @override
  void initState() {
    super.initState();
    _showReminder = widget.activeCourse == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.of(context);
    if (_tickerEnabled == tickerEnabled) return;

    _tickerEnabled = tickerEnabled;
    _restartTimer(resetToCourse: tickerEnabled);
  }

  @override
  void didUpdateWidget(covariant _RotatingLearningCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotationInterval != widget.rotationInterval) {
      _restartTimer(resetToCourse: true);
    }
  }

  void _restartTimer({required bool resetToCourse}) {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    if (resetToCourse) _showReminder = widget.activeCourse == null;
    if (!_tickerEnabled ||
        widget.activeCourse == null ||
        widget.rotationInterval <= Duration.zero) {
      return;
    }

    _rotationTimer = Timer.periodic(widget.rotationInterval, (_) {
      if (!mounted) return;
      setState(() => _showReminder = !_showReminder);
    });
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeCourse = widget.activeCourse;
    final promptCourse = activeCourse ?? widget.unstartedCourse;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final fill = isDark ? scheme.surfaceContainerHighest : AppColors.primary;
    final fg = isDark ? scheme.onSurface : Colors.white;
    final track = fg.withValues(alpha: 0.24);
    final progress = activeCourse == null
        ? 0.0
        : ((activeCourse.userProgress ?? 0) / 100).clamp(0.0, 1.0);

    void openTarget() {
      if (promptCourse == null) {
        LearnerRoute.push(context, (_) => const CourseListScreen());
        return;
      }

      trackContentInteraction(
        itemType: 'course',
        itemId: promptCourse.id,
        action: 'open',
        topic: promptCourse.tags.isNotEmpty ? promptCourse.tags.first : null,
        source: _showReminder ? 'home_learning_reminder' : 'home_continue',
      );
      LearnerRoute.push(
        context,
        (_) => CourseDetailScreen(courseId: promptCourse.id),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openTarget,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: !_showReminder && activeCourse != null
                    ? _ContinueCourseContent(
                        key: ValueKey('course:${activeCourse.id}'),
                        course: activeCourse,
                        progress: progress,
                        theme: theme,
                        foreground: fg,
                        track: track,
                        fill: fill,
                        isDark: isDark,
                        onPressed: openTarget,
                      )
                    : _LearningReminderContent(
                        key: ValueKey(
                          'reminder:${promptCourse?.id ?? 'discover'}',
                        ),
                        course: promptCourse,
                        hasActiveCourse: activeCourse != null,
                        theme: theme,
                        foreground: fg,
                        fill: fill,
                        isDark: isDark,
                        onPressed: openTarget,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueCourseContent extends StatelessWidget {
  const _ContinueCourseContent({
    super.key,
    required this.course,
    required this.progress,
    required this.theme,
    required this.foreground,
    required this.track,
    required this.fill,
    required this.isDark,
    required this.onPressed,
  });

  final CourseEntity course;
  final double progress;
  final ThemeData theme;
  final Color foreground;
  final Color track;
  final Color fill;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LeadingDisc(
          icon: PhosphorIconsBold.bookOpenText,
          foreground: foreground,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'home.continueLearningSection'.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground.withValues(alpha: 0.85),
                ),
              ),
              Text(
                course.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: progress,
                        backgroundColor: track,
                        valueColor: AlwaysStoppedAnimation<Color>(foreground),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(progress * 100).round()}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _CardActionButton(
          icon: PhosphorIconsFill.play,
          tooltip: 'home.continueLesson'.tr(),
          foreground: foreground,
          fill: fill,
          isDark: isDark,
          onPressed: onPressed,
        ),
      ],
    );
  }
}

class _LearningReminderContent extends StatelessWidget {
  const _LearningReminderContent({
    super.key,
    required this.course,
    required this.hasActiveCourse,
    required this.theme,
    required this.foreground,
    required this.fill,
    required this.isDark,
    required this.onPressed,
  });

  final CourseEntity? course;
  final bool hasActiveCourse;
  final ThemeData theme;
  final Color foreground;
  final Color fill;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hasUnstartedCourse = course != null && !hasActiveCourse;
    final labelKey = hasActiveCourse
        ? 'home.keepGoing'
        : hasUnstartedCourse
        ? 'home.startLesson'
        : 'home.startLearning';
    final message = hasActiveCourse
        ? 'home.completeLessonToday'.tr()
        : hasUnstartedCourse
        ? course!.title
        : 'home.enrollCoursePrompt'.tr();

    return Row(
      children: [
        _LeadingDisc(
          icon: hasActiveCourse
              ? PhosphorIconsBold.bell
              : PhosphorIconsBold.sparkle,
          foreground: foreground,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labelKey.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _CardActionButton(
          icon: course == null
              ? PhosphorIconsBold.arrowRight
              : PhosphorIconsFill.play,
          tooltip: course == null
              ? 'home.startLearning'.tr()
              : 'home.startLesson'.tr(),
          foreground: foreground,
          fill: fill,
          isDark: isDark,
          onPressed: onPressed,
        ),
      ],
    );
  }
}

class _LeadingDisc extends StatelessWidget {
  const _LeadingDisc({required this.icon, required this.foreground});

  final IconData icon;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: foreground.withValues(alpha: 0.18),
      ),
      child: Icon(icon, color: foreground, size: 22),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.icon,
    required this.tooltip,
    required this.foreground,
    required this.fill,
    required this.isDark,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color foreground;
  final Color fill;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: isDark ? AppColorRoles.primary(true) : foreground,
        foregroundColor: isDark ? Theme.of(context).colorScheme.surface : fill,
        fixedSize: const Size(44, 44),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}
