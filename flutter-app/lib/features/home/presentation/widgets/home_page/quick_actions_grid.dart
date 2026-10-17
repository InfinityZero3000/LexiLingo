import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/circle_icon.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/pages/vocab_library_page.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Quick Actions - one card holding a grid of icon discs
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    // Keep all dark-mode quick actions in a consistent neon range.
    const neonDarkActionColors = <Color>[
      Color(0xFFFF3131), // YouTube
      Color(0xFFFC1AD3), // News
      Color(0xFFFFA319), // Games
      Color(0xFF35FF0D), // Podcast
      Color(0xFF8B5CFF), // Books (neon purple)
      Color(0xFFFF369E), // Vocabulary
    ];

    final quickActions = [
      (
        icon: PhosphorIconsBold.youtubeLogo,
        label: 'home.youtube',
        color: isDark ? neonDarkActionColors[0] : AppColors.dangerGradient[0],
        route: '/youtube',
      ),
      (
        icon: PhosphorIconsBold.newspaper,
        label: 'home.news',
        color: isDark ? neonDarkActionColors[1] : AppColors.teal,
        route: '/news',
      ),
      (
        icon: PhosphorIconsBold.gameController,
        label: 'home.games',
        color: isDark ? neonDarkActionColors[2] : AppColors.purple,
        route: '/games',
      ),
      (
        icon: PhosphorIconsBold.headphones,
        label: 'home.podcast',
        color: isDark ? neonDarkActionColors[3] : accent,
        route: '/podcast',
      ),
      (
        icon: PhosphorIconsBold.bookOpenText,
        label: 'home.books',
        color: isDark ? neonDarkActionColors[4] : AppColors.purpleLight,
        route: '/books',
      ),
      (
        icon: PhosphorIconsBold.cards,
        label: 'home.vocabulary',
        color: isDark ? neonDarkActionColors[5] : AppColors.orange,
        route: '/vocab',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
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
            final columns = constraints.maxWidth >= 960
                ? quickActions.length
                : constraints.maxWidth >= 640
                ? 4
                : 3;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 18,
                mainAxisExtent: 96,
              ),
              itemCount: quickActions.length,
              itemBuilder: (context, index) {
                final action = quickActions[index];
                return _QuickActionTile(
                  icon: action.icon,
                  label: action.label.tr(),
                  color: action.color,
                  onTap: () {
                    if (action.route == '/vocab') {
                      LearnerRoute.push(
                        context,
                        (_) => const VocabLibraryPage(),
                      );
                    } else {
                      Navigator.pushNamed(context, action.route);
                    }
                  },
                );
              },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkResponse(
      onTap: onTap,
      radius: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleIcon(icon: icon, color: color, size: 60),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: AppColorRoles.textPrimary(isDark),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
