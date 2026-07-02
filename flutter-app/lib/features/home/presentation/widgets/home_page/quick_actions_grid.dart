import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/pages/vocab_library_page.dart';

/// Quick Actions - Horizontal scrollable section with circular buttons
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    // Keep all dark-mode quick actions in a consistent neon range.
    const neonDarkActionColors = <Color>[
      Color(0xFF00E5FF), // Practice Lab
      Color(0xFFFF3131), // YouTube
      Color(0xFFFC1AD3), // News
      Color(0xFFFFA319), // Games
      Color(0xFF35FF0D), // Podcast
      Color(0xFF8B5CFF), // Books (neon purple)
      Color(0xFFFF369E), // Vocabulary
    ];

    final quickActions = [
      {
        'icon': Icons.science_rounded,
        'label': 'practiceLab.shortTitle',
        'color': isDark ? neonDarkActionColors[0] : AppColors.primary,
        'bgColor': (isDark ? neonDarkActionColors[0] : AppColors.primary)
            .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/practice-lab',
      },
      {
        'icon': GameIcon.video,
        'label': 'home.youtube',
        'color': isDark ? neonDarkActionColors[1] : AppColors.dangerGradient[0],
        'bgColor':
            (isDark ? neonDarkActionColors[1] : AppColors.dangerGradient[0])
                .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/youtube',
      },
      {
        'icon': GameIcon.newspaper,
        'label': 'home.news',
        'color': isDark ? neonDarkActionColors[2] : AppColors.teal,
        'bgColor': (isDark ? neonDarkActionColors[2] : AppColors.teal)
            .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/news',
      },
      {
        'icon': GameIcon.gameController,
        'label': 'home.games',
        'color': isDark ? neonDarkActionColors[3] : AppColors.purple,
        'bgColor': (isDark ? neonDarkActionColors[3] : AppColors.purple)
            .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/games',
      },
      {
        'icon': GameIcon.headphones,
        'label': 'home.podcast',
        'color': isDark ? neonDarkActionColors[4] : accent,
        'bgColor': (isDark ? neonDarkActionColors[4] : accent).withValues(
          alpha: isDark ? 0.16 : 0.12,
        ),
        'route': '/podcast',
      },
      {
        'icon': GameIcon.book,
        'label': 'home.books',
        'color': isDark ? neonDarkActionColors[5] : AppColors.purpleLight,
        'bgColor': (isDark ? neonDarkActionColors[5] : AppColors.purple)
            .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/books',
      },
      {
        'icon': GameIcon.vocabulary,
        'label': 'home.vocabulary',
        'color': isDark ? neonDarkActionColors[6] : AppColors.orange,
        'bgColor': (isDark ? neonDarkActionColors[6] : AppColors.warning)
            .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/vocab',
      },
    ];

    const crossAxisCount = 3;
    const spacing = 12.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth =
              (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
              crossAxisCount;
          // Scale the icon (and tile height) with tile width instead of a
          // fixed aspect ratio, so narrow screens don't overflow vertically.
          final iconSize = (tileWidth * 0.42).clamp(34.0, 44.0);
          final tileHeight = iconSize + 56;

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              mainAxisExtent: tileHeight,
            ),
            itemCount: quickActions.length,
            itemBuilder: (context, index) {
              final action = quickActions[index];
              return _QuickActionChip(
                icon: action['icon']!,
                label: (action['label'] as String).tr(),
                color: action['color'] as Color,
                bgColor: action['bgColor'] as Color,
                iconSize: iconSize,
                onTap: () {
                  final route = action['route'] as String;
                  if (route == '/vocab') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VocabLibraryPage(),
                      ),
                    );
                  } else {
                    Navigator.pushNamed(context, route);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final Object icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;
  final double iconSize;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
    this.iconSize = 44,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fontSize = iconSize <= 38 ? 9.0 : 10.0;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.5 : 0.35),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: isDark ? 0.5 : 0.35),
                    blurRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: icon is GameIcon
                  ? AppGameIcon(
                      icon as GameIcon,
                      size: iconSize * 0.5,
                      fallbackColor: surfaceColor,
                    )
                  : Icon(
                      icon as IconData,
                      color: surfaceColor,
                      size: iconSize * 0.5,
                    ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
