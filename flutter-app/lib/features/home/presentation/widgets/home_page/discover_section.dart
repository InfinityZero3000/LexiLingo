import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/books/presentation/screens/book_detail_screen.dart';
import 'package:lexilingo_app/features/books/presentation/widgets/book_card.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/course_level_helpers.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/discover_data.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/section_title.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';

/// One card at the foot of Home: the book of the week, plus a podcast and a
/// course the learner has not started, all picked for their level.
class DiscoverSection extends StatefulWidget {
  const DiscoverSection({super.key, this.loader = loadDiscoverFeed});

  final Future<DiscoverFeed> Function(String level) loader;

  @override
  State<DiscoverSection> createState() => _DiscoverSectionState();
}

class _DiscoverSectionState extends State<DiscoverSection> {
  String? _level;
  late Future<DiscoverFeed> _future;

  @override
  void initState() {
    super.initState();
    // Nothing else loads the profile before Home, and an unloaded one reads A1.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProficiencyProvider>().loadProfile();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final level = Provider.of<ProficiencyProvider>(context).assessedLevel;
    if (level == _level) return;
    _level = level;
    _future = widget.loader(level).catchError((_) => const DiscoverFeed());
  }

  Future<void> _openBook(Book book) async {
    trackContentInteraction(
      itemType: 'book',
      itemId: book.id,
      action: 'open',
      source: 'home_discover',
    );
    await context.read<BookProvider>().openBook(book);
    if (!mounted) return;
    LearnerRoute.push(context, (_) => BookDetailScreen(book: book));
  }

  void _openPodcast(Podcast podcast) {
    trackContentInteraction(
      itemType: 'podcast',
      itemId: podcast.id,
      action: 'open',
      source: 'home_discover',
    );
    Navigator.pushNamed(context, '/podcast/detail', arguments: podcast);
  }

  void _openCourse(CourseEntity course) {
    trackContentInteraction(
      itemType: 'course',
      itemId: course.id,
      action: 'open',
      source: 'home_discover',
    );
    LearnerRoute.push(context, (_) => CourseDetailScreen(courseId: course.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = AppColorRoles.textMuted(isDark);
    final tactile =
        theme.extension<AppTactileTheme>() ?? AppTactileTheme.from(theme);

    return FutureBuilder<DiscoverFeed>(
      future: _future,
      builder: (context, snapshot) {
        final feedLoading = snapshot.connectionState != ConnectionState.done;
        final feed = snapshot.data ?? const DiscoverFeed();

        return Consumer<HomeProvider>(
          builder: (context, home, _) {
            final course = home.featuredCourses
                .where((c) => c.isEnrolled != true)
                .firstOrNull;
            final loading =
                feedLoading ||
                (home.isLoadingCourses && home.featuredCourses.isEmpty);
            final hasContent =
                feed.book != null || feed.podcast != null || course != null;
            if (!hasContent && !loading) return const SizedBox.shrink();

            final rows = [
              if (feed.podcast case final podcast?)
                _DiscoverRow(
                  icon: PhosphorIconsBold.headphones,
                  color: isDark ? AppColors.purpleLight : AppColors.purple,
                  title: podcast.title,
                  subtitle: 'home.discoverPodcastMeta'
                      .tr(
                        namedArgs: {
                          'level': podcast.cefrLevel,
                          'author': podcast.author,
                        },
                      )
                      .replaceFirst(RegExp(r'\s*·\s*$'), ''),
                  onTap: () => _openPodcast(podcast),
                ),
              if (course != null)
                _DiscoverRow(
                  icon: Icons.school_outlined,
                  color: AppColorRoles.primary(isDark),
                  title: course.title,
                  subtitle: 'home.discoverCourseMeta'.tr(
                    namedArgs: {
                      'difficulty': localizedCourseLevel(course.level),
                      'count': '${course.totalLessons}',
                    },
                  ),
                  onTap: () => _openCourse(course),
                ),
            ];

            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(title: 'home.discover'.tr()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'home.discoverSubtitle'.tr(
                        namedArgs: {'level': _level ?? ''},
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      24,
                    ),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: tactile.decoration(
                        variant: TactileSurfaceVariant.clean,
                        fill: isDark
                            ? theme.colorScheme.surfaceContainerHighest
                            : theme.colorScheme.surface,
                        accent: AppColorRoles.primary(isDark),
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        diagnosticId: 'home-discover',
                      ),
                      child: !hasContent
                          ? const _DiscoverSkeleton()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (feed.book case final book?)
                                  _BookOfWeek(
                                    book: book,
                                    onOpen: () => _openBook(book),
                                  ),
                                if (feed.book != null && rows.isNotEmpty)
                                  Divider(
                                    height: 1,
                                    color: theme.dividerColor.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                if (rows.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppSpacing.sm,
                                      AppSpacing.sm,
                                      AppSpacing.sm,
                                      AppSpacing.sm,
                                    ),
                                    child: Column(children: rows),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _BookOfWeek extends StatelessWidget {
  const _BookOfWeek({required this.book, required this.onOpen});

  final Book book;
  final VoidCallback onOpen;

  static const double _coverWidth = 84;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = AppColorRoles.textMuted(isDark);

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(
              book: book,
              width: _coverWidth,
              height: _coverWidth * 3 / 2,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'home.bookOfWeek'.tr(),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: muted,
                        ),
                      ),
                      CefrBadge(level: book.cefrLevel),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (book.author.isNotEmpty)
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  if (book.chapterCount > 0)
                    Text(
                      'home.bookChapters'.tr(
                        namedArgs: {'count': '${book.chapterCount}'},
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        shape: const StadiumBorder(),
                      ),
                      child: Text('home.readNow'.tr()),
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
}

class _DiscoverRow extends StatelessWidget {
  const _DiscoverRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = AppColorRoles.textMuted(isDark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 8,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverSkeleton extends StatelessWidget {
  const _DiscoverSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLoader(width: 84, height: 126, borderRadius: 10),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(height: 12, width: 96),
                SizedBox(height: 10),
                SkeletonLoader(height: 18),
                SizedBox(height: 8),
                SkeletonLoader(height: 12, width: 120),
                SizedBox(height: 16),
                SkeletonLoader(height: 44, borderRadius: 22),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
