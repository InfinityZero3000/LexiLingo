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
    // One saturated hue per tile, no two from the same family.
    const lightActionColors = <Color>[
      Color(0xFFFF4B4B), // YouTube
      Color(0xFF14C38E), // News
      Color(0xFF8B5CF6), // Games
      Color(0xFF1CB0F6), // Podcast
      Color(0xFFFF5FA2), // Books
      Color(0xFFFF9F0A), // Vocabulary
    ];
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
        color: isDark ? neonDarkActionColors[0] : lightActionColors[0],
        route: '/youtube',
      ),
      (
        icon: PhosphorIconsBold.newspaper,
        label: 'home.news',
        color: isDark ? neonDarkActionColors[1] : lightActionColors[1],
        route: '/news',
      ),
      (
        icon: PhosphorIconsBold.gameController,
        label: 'home.games',
        color: isDark ? neonDarkActionColors[2] : lightActionColors[2],
        route: '/games',
      ),
      (
        icon: PhosphorIconsBold.headphones,
        label: 'home.podcast',
        color: isDark ? neonDarkActionColors[3] : lightActionColors[3],
        route: '/podcast',
      ),
      (
        icon: PhosphorIconsBold.bookOpenText,
        label: 'home.books',
        color: isDark ? neonDarkActionColors[4] : lightActionColors[4],
        route: '/books',
      ),
      (
        icon: PhosphorIconsBold.cards,
        label: 'home.vocabulary',
        color: isDark ? neonDarkActionColors[5] : lightActionColors[5],
        route: '/vocab',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
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
              // A null padding inherits the bottom nav inset as dead space.
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 10,
                mainAxisExtent: 88,
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
          CircleIcon(icon: icon, color: color, size: 56),
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
