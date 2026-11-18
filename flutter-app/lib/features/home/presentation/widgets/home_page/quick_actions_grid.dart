import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/circle_icon.dart';
import 'package:lexilingo_app/features/home/presentation/pages/main_screen.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/pages/vocab_library_page.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Quick Actions - one card holding a grid of icon discs
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key, this.lockSecondary = false});

  /// Until the learner finishes a first lesson only the four starting tiles
  /// show (lessons, Lexi, vocabulary, games); the other routes remain registered, so deep links still open them.
  final bool lockSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final allActions = [
      (
        icon: PhosphorIconsBold.graduationCap,
        label: 'home.navLearning',
        color: AppColors.primary,
        route: '/courses',
        tab: MainScreen.learningTab,
        alwaysOn: true,
      ),
      (
        icon: PhosphorIconsBold.chatCircleDots,
        label: 'home.navLexi',
        color: AppColors.teal,
        route: '/lexi',
        tab: MainScreen.lexiTab,
        alwaysOn: true,
      ),
      (
        icon: PhosphorIconsBold.translate,
        label: 'home.vocabulary',
        color: AppColors.orange,
        route: '/vocab',
        tab: null,
        alwaysOn: true,
      ),
      (
        icon: PhosphorIconsBold.gameController,
        label: 'home.games',
        color: AppColors.purple,
        route: '/games',
        tab: null,
        alwaysOn: true,
      ),
      (
        icon: PhosphorIconsBold.playCircle,
        label: 'home.youtube',
        color: AppColors.errorBright,
        route: '/youtube',
        tab: null,
        alwaysOn: false,
      ),
      (
        icon: PhosphorIconsBold.newspaper,
        label: 'home.news',
        color: AppColors.greenSuccessBright,
        route: '/news',
        tab: null,
        alwaysOn: false,
      ),
      (
        icon: PhosphorIconsBold.headphones,
        label: 'home.podcast',
        color: AppColors.skyBlue,
        route: '/podcast',
        tab: null,
        alwaysOn: false,
      ),
      (
        icon: PhosphorIconsBold.bookOpenText,
        label: 'home.books',
        color: AppColors.pink,
        route: '/books',
        tab: null,
        alwaysOn: false,
      ),
    ];
    final quickActions = lockSecondary
        ? allActions.where((action) => action.alwaysOn).toList()
        : allActions;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 4 per row (8 tiles = two full rows) or a single row when wide.
            final columns = constraints.maxWidth >= 560
                ? quickActions.length
                : 4;
            // Tiles size to their text, so a larger font scale grows the row
            // instead of overflowing a fixed extent.
            final tileWidth = (constraints.maxWidth / columns).floorToDouble();
            final grid = Wrap(
              runSpacing: 12,
              children: [
                for (final action in quickActions)
                  SizedBox(
                    width: tileWidth,
                    child: _QuickActionTile(
                      icon: action.icon,
                      label: action.label.tr(),
                      color: action.color,
                      onTap: () {
                        final tab = action.tab;
                        if (tab != null && MainScreen.switchTab(context, tab)) {
                          return;
                        }
                        if (action.route == '/vocab') {
                          LearnerRoute.push(
                            context,
                            (_) => const VocabLibraryPage(),
                          );
                        } else {
                          Navigator.pushNamed(context, action.route);
                        }
                      },
                    ),
                  ),
              ],
            );
            if (!lockSecondary) return grid;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                grid,
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                    0,
                  ),
                  child: Text(
                    'home.unlockHint'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 48,
        highlightShape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleIcon(icon: icon, color: color, size: 52),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: AppColorRoles.textPrimary(isDark),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
