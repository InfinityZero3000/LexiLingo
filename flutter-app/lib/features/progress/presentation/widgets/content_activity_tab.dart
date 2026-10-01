import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/progress/domain/entities/content_activity_entity.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/content_activity_provider.dart';

/// The Content tab of the weekly overview.
///
/// Shows what the library, podcast, video and news surfaces were credited for,
/// read from the server's immutable XP transaction rows. Sources that report
/// time show minutes; news and books are credited on the quiz, so they show a
/// count — "0 minutes" there would read as a broken counter.
class ContentActivityTab extends StatefulWidget {
  const ContentActivityTab({super.key});

  @override
  State<ContentActivityTab> createState() => _ContentActivityTabState();
}

class _ContentActivityTabState extends State<ContentActivityTab> {
  @override
  void initState() {
    super.initState();
    // Lazy: nothing fetches this until the tab is first built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ContentActivityProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<ContentActivityProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.activity.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.errorMessage != null && provider.activity.isEmpty) {
          return _CenteredNote(
            icon: Icons.cloud_off_rounded,
            message: 'contentActivity.loadFailed'.tr(),
            isDark: isDark,
            onRetry: () => provider.load(force: true),
          );
        }
        if (provider.activity.bySource.isEmpty) {
          return _CenteredNote(
            icon: Icons.explore_outlined,
            message: 'contentActivity.empty'.tr(),
            isDark: isDark,
          );
        }

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _Summary(activity: provider.activity, isDark: isDark),
            const SizedBox(height: 12),
            for (final source in provider.activity.bySource)
              _SourceRow(source: source, isDark: isDark),
          ],
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.activity, required this.isDark});

  final ContentActivityEntity activity;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      'contentActivity.summary'.tr(
        namedArgs: {
          'days': '${activity.days}',
          'minutes': '${activity.totalMinutes}',
          'sessions': '${activity.totalSessions}',
          'xp': '${activity.totalXp}',
        },
      ),
      style: TextStyle(fontSize: 13, color: AppColorRoles.textMuted(isDark)),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.isDark});

  final ContentSourceActivityEntity source;
  final bool isDark;

  static const _icons = {
    'youtube': Icons.ondemand_video_rounded,
    'podcast': Icons.podcasts_rounded,
    'news': Icons.article_rounded,
    'book': Icons.menu_book_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final muted = AppColorRoles.textMuted(isDark);
    final primary = AppColorRoles.primary(isDark);

    // A source that reports time shows minutes; one credited per activity shows
    // how many it credited. Never minutes for the latter — it is always 0.
    final headline = source.tracksMinutes
        ? 'contentActivity.minutes'.tr(namedArgs: {'value': '${source.minutes}'})
        : 'contentActivity.sessions'.tr(
            namedArgs: {'value': '${source.sessions}'},
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: source.hasActivity
                  ? primary.withValues(alpha: 0.12)
                  : (isDark ? AppColors.surfaceDarkMuted : AppColors.grey100),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              _icons[source.source] ?? Icons.play_circle_outline_rounded,
              size: 18,
              color: source.hasActivity ? primary : muted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'contentActivity.source.${source.source}'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  source.hasActivity
                      ? headline
                      : 'contentActivity.notYet'.tr(),
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          if (source.xpEarned > 0)
            Text(
              '+${source.xpEarned} XP',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
        ],
      ),
    );
  }
}

class _CenteredNote extends StatelessWidget {
  const _CenteredNote({
    required this.icon,
    required this.message,
    required this.isDark,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final bool isDark;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = AppColorRoles.textMuted(isDark);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: muted),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text('common.retry'.tr()),
            ),
        ],
      ),
    );
  }
}
