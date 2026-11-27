import 'package:lexilingo_app/core/navigation/reload_on_return.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/network/course_network_image.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/l10n/locale_keys.g.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_detail_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_session_screen.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_roadmap_screen.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/onboarding/presentation/start_learning_launcher.dart';
import 'package:lexilingo_app/core/widgets/app_surface.dart';
import 'package:lexilingo_app/features/course/presentation/utils/course_labels.dart';

/// Course Detail Screen
/// Shows course roadmap with units and lessons
class CourseDetailScreen extends StatefulWidget {
  final String courseId;
  final String? heroTag;
  final String? initialThumbnailUrl;
  final String? fallbackThumbnailUrl;

  const CourseDetailScreen({
    super.key,
    required this.courseId,
    this.heroTag,
    this.initialThumbnailUrl,
    this.fallbackThumbnailUrl,
  });

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen>
    with ReloadOnReturn {
  @override
  void reload() =>
      context.read<CourseProvider>().loadCourseDetail(widget.courseId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CourseProvider>().loadCourseDetail(widget.courseId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CourseProvider>(
      builder: (context, provider, child) {
        final course = provider.courseDetail;
        final loading = provider.isLoadingDetail && course == null;
        final scheme = Theme.of(context).colorScheme;

        Widget body;
        if (loading) {
          body = const Center(child: LottieLoadingWidget.medium());
        } else if (provider.detailError != null && course == null) {
          body = _DetailError(
            onRetry: () => provider.loadCourseDetail(widget.courseId),
          );
        } else if (course == null) {
          body = Center(child: Text('course.notFound'.tr()));
        } else {
          body = _buildContent(context, provider, course);
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            titleSpacing: 0,
            title: Text(
              course?.title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          body: ContentWidth(child: body),
          bottomNavigationBar: course == null
              ? null
              : _buildActionBar(context, provider, course),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    CourseProvider provider,
    CourseDetailEntity course,
  ) {
    final theme = Theme.of(context);
    final nextLessonId = course.nextOpenLesson?.id;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCourseHeroCard(context, course),
                const SizedBox(height: AppSpacing.lg),
                if (course.description != null) ...[
                  Text(
                    course.description!,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _StatChip(
                      icon: Icons.bar_chart_rounded,
                      label: courseLevelLabel(course.level),
                    ),
                    _StatChip(
                      icon: Icons.menu_book_rounded,
                      label: 'course.totalLessonsCount'.tr(
                        namedArgs: {'count': '${course.totalLessons}'},
                      ),
                    ),
                    _StatChip(
                      icon: Icons.schedule_rounded,
                      label: 'course.durationMin'.tr(
                        namedArgs: {'count': '${course.estimatedDuration}'},
                      ),
                    ),
                    _StatChip(
                      icon: Icons.star_rounded,
                      label: '${course.totalXp} XP',
                    ),
                  ],
                ),
                if (course.isEnrolled == true) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ProgressPanel(
                    percent: course.userProgress ?? 0,
                    onRoadmap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LearningRoadmapScreen(
                          courseId: course.id,
                          courseTitle: course.title,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'course.learningRoadmap'.tr(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            return _UnitCard(
              unit: course.units[index],
              unitNumber: index + 1,
              courseId: course.id,
              nextLessonId: nextLessonId,
            );
          }, childCount: course.units.length),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }

  Widget? _buildActionBar(
    BuildContext context,
    CourseProvider provider,
    CourseDetailEntity course,
  ) {
    final enrolled = course.isEnrolled == true;
    final next = course.nextOpenLesson;
    if (enrolled && next == null) return null;

    final VoidCallback? onPressed;
    final Widget label;
    final Widget icon;
    if (enrolled) {
      onPressed = () => _openLesson(context, course.id, next!.id);
      label = Text(
        '${'course.continue'.tr()}: ${next!.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      icon = const Icon(Icons.play_arrow_rounded);
    } else {
      onPressed = provider.isEnrolling
          ? null
          : () => _enrollInCourse(context, provider);
      label = Text(
        provider.isEnrolling
            ? 'course.enrolling'.tr()
            : 'course.startLearning'.tr(),
      );
      icon = provider.isEnrolling
          ? const SizedBox(
              width: 20,
              height: 20,
              child: LottieLoadingWidget.tiny(),
            )
          : const Icon(Icons.play_arrow_rounded);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: ContentWidth(
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: icon,
              label: label,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(kMinTapTarget + 8),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _enrollInCourse(
    BuildContext context,
    CourseProvider provider,
  ) async {
    await StartLearningLauncher.open(context, courseId: widget.courseId);
    if (!mounted) return;
    provider.loadCourseDetail(widget.courseId);
  }

  Widget _buildCourseHeroCard(BuildContext context, CourseDetailEntity course) {
    final heroImage = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _buildCourseBackground(
          context,
          course,
          cacheScopeKey: widget.heroTag ?? widget.courseId,
        ),
      ),
    );

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.slate900.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: widget.heroTag != null
          ? Hero(tag: widget.heroTag!, child: heroImage)
          : heroImage,
    );
    // Full width on a tablet makes the cover 400 px tall and pushes the
    // roadmap off the first screen.
    if (!ContentWidth.isTablet(MediaQuery.sizeOf(context).width)) return card;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: card,
      ),
    );
  }

  Widget _buildCourseBackground(
    BuildContext context,
    CourseDetailEntity course, {
    required String cacheScopeKey,
  }) {
    final imageUrls = buildCourseThumbnailCandidates(
      detailThumbnailUrl: course.thumbnailUrl,
      initialThumbnailUrl: widget.initialThumbnailUrl,
      fallbackThumbnailUrl: widget.fallbackThumbnailUrl,
    );

    if (imageUrls.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _CourseHeroNetworkImage(
            imageUrls: imageUrls,
            placeholder: _buildCourseImagePlaceholder(context),
            cacheScopeKey: cacheScopeKey,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.slate900.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return _buildCourseImagePlaceholder(context);
  }

  Widget _buildCourseImagePlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).primaryColor,
      child: Icon(
        Icons.school,
        size: 64,
        color: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}

List<String> buildCourseThumbnailCandidates({
  String? detailThumbnailUrl,
  String? initialThumbnailUrl,
  String? fallbackThumbnailUrl,
}) {
  final candidates = <String>[];

  for (final value in [
    detailThumbnailUrl,
    initialThumbnailUrl,
    fallbackThumbnailUrl,
  ]) {
    final url = value?.trim();
    if (url != null && url.isNotEmpty && !candidates.contains(url)) {
      candidates.add(url);
    }
  }

  return candidates;
}

class _CourseHeroNetworkImage extends StatelessWidget {
  final List<String> imageUrls;
  final Widget placeholder;
  final String cacheScopeKey;

  const _CourseHeroNetworkImage({
    required this.imageUrls,
    required this.placeholder,
    required this.cacheScopeKey,
  });

  @override
  Widget build(BuildContext context) {
    return _buildCandidate(0);
  }

  Widget _buildCandidate(int index) {
    if (index >= imageUrls.length) {
      return placeholder;
    }

    return CourseNetworkImage(
      url: imageUrls[index],
      placeholder: placeholder,
      onError: () => _buildCandidate(index + 1),
      memCacheWidth: 960,
    );
  }
}

Future<void> _openLesson(
  BuildContext context,
  String courseId,
  String lessonId,
) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) =>
          LearningSessionScreen(lessonId: lessonId, courseId: courseId),
    ),
  );
}

class _DetailError extends StatelessWidget {
  final VoidCallback onRetry;
  const _DetailError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: scheme.error),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'common.error'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onRetry, child: Text('common.retry'.tr())),
          ],
        ),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  final double percent;
  final VoidCallback onRoadmap;
  const _ProgressPanel({required this.percent, required this.onRoadmap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSurface(
      radius: BorderRadius.circular(AppRadius.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'course.yourProgress'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'course.userProgressPercent'.tr(
                  namedArgs: {'percent': percent.toStringAsFixed(0)},
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onRoadmap,
              child: Text('course.viewFullRoadmap'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppColorRoles.primary(theme.brightness == Brightness.dark);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  final UnitWithLessonsEntity unit;
  final int unitNumber;
  final String courseId;
  final String? nextLessonId;

  const _UnitCard({
    required this.unit,
    required this.unitNumber,
    required this.courseId,
    this.nextLessonId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final done = unit.lessons.where((l) => l.isCompleted ?? false).length;
    final progress = '$done/${unit.lessons.length}';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: AppSurface(
        radius: BorderRadius.circular(AppRadius.lg),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            initiallyExpanded: unit.lessons.any((l) => l.id == nextLessonId),
            leading: CircleAvatar(
              backgroundColor: _parseColor(unit.backgroundColor, isDark),
              child: Text(
                '$unitNumber',
                style: TextStyle(
                  color: theme.colorScheme.surface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              unit.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              unit.description == null
                  ? progress
                  : '${unit.description!}  ·  $progress',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              for (final lesson in unit.lessons)
                _LessonTile(
                  lesson: lesson,
                  courseId: courseId,
                  isNext: lesson.id == nextLessonId,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseColor(String? colorString, bool isDark) {
    if (colorString == null || colorString.isEmpty) {
      return AppColorRoles.primary(isDark);
    }
    try {
      return Color(int.parse(colorString.replaceFirst('#', '0xFF')));
    } catch (e) {
      return AppColorRoles.primary(isDark);
    }
  }
}

class _LessonTile extends StatelessWidget {
  final LessonInRoadmapEntity lesson;
  final String courseId;
  final bool isNext;

  const _LessonTile({
    required this.lesson,
    required this.courseId,
    this.isNext = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLocked = lesson.isLocked ?? false;
    final isCompleted = lesson.isCompleted ?? false;
    final isDark = theme.brightness == Brightness.dark;
    final muted = scheme.onSurfaceVariant;

    return ListTile(
      minTileHeight: kMinTapTarget,
      leading: _lessonIcon(context, isLocked, isCompleted, isDark),
      title: Text(
        lesson.title,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: isLocked || isCompleted ? muted : scheme.onSurface,
          fontWeight: isNext ? FontWeight.w700 : null,
        ),
      ),
      subtitle: isNext
          ? Text(
              LocaleKeys.course_nextUp.tr(),
              style: TextStyle(
                color: AppColorRoles.primary(isDark),
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 16, color: AppColors.accentYellow),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${lesson.xpReward}',
            style: theme.textTheme.labelMedium?.copyWith(color: muted),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (isCompleted)
            Icon(Icons.check_circle_rounded, color: context.status.success)
          else if (isLocked)
            Icon(Icons.lock_rounded, color: muted)
          else
            Icon(
              Icons.play_circle_outline_rounded,
              color: AppColorRoles.primary(isDark),
            ),
        ],
      ),
      onTap: isLocked
          ? () => ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text(LocaleKeys.course_lockedHint.tr())),
              )
          : () => _openLesson(context, courseId, lesson.id),
    );
  }

  Widget _lessonIcon(
    BuildContext context,
    bool isLocked,
    bool isCompleted,
    bool isDark,
  ) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (isLocked) return Icon(Icons.lock_rounded, color: muted);
    if (isCompleted) {
      return Icon(Icons.check_circle_rounded, color: context.status.success);
    }
    final (IconData icon, Color color) = switch (lesson.lessonType
        .toLowerCase()) {
      'vocabulary' => (Icons.school_rounded, AppColorRoles.primary(isDark)),
      'grammar' => (Icons.menu_book_rounded, AppColors.orange),
      'listening' => (Icons.headphones_rounded, AppColors.purple),
      'speaking' => (Icons.mic_rounded, AppColors.errorBright),
      'reading' => (Icons.book_rounded, AppColors.teal),
      'writing' => (Icons.edit_rounded, AppColors.primaryDark),
      'quiz' => (Icons.quiz_rounded, AppColors.warning),
      _ => (Icons.article_rounded, muted),
    };
    return Icon(icon, color: color);
  }
}
