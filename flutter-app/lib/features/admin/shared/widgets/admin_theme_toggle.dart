import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:provider/provider.dart';
import '../../core/theme/admin_theme_controller.dart';

AdminThemeController? maybeAdminThemeController(BuildContext context) {
  try {
    return Provider.of<AdminThemeController>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

/// Compact AppBar action that toggles the Admin panel between Light and Dark
/// backgrounds with one tap.
class AdminThemeToggleButton extends StatelessWidget {
  const AdminThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = maybeAdminThemeController(context);
    if (controller == null) return const SizedBox.shrink();

    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark
          ? 'admin.shell.themeLight'.tr()
          : 'admin.shell.themeDark'.tr(),
      constraints: const BoxConstraints(
        minWidth: kMinTapTarget,
        minHeight: kMinTapTarget,
      ),
      icon: Icon(
        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
        size: 20,
      ),
      onPressed: () => controller.toggle(brightness),
    );
  }
}

/// 3-way background selector (Light / Dark / System) displayed inside the
/// navigation drawer so admins can switch themes from any screen.
class AdminThemeModeSelector extends StatelessWidget {
  const AdminThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = maybeAdminThemeController(context);
    if (controller == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = controller.mode;

    final options = <(ThemeMode, IconData, String)>[
      (
        ThemeMode.light,
        Icons.light_mode_rounded,
        'admin.shell.themeLight'.tr(),
      ),
      (ThemeMode.dark, Icons.dark_mode_rounded, 'admin.shell.themeDark'.tr()),
      (
        ThemeMode.system,
        Icons.brightness_auto_rounded,
        'admin.shell.themeSystem'.tr(),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            for (final (mode, icon, label) in options)
              Expanded(
                child: InkWell(
                  borderRadius: AppRadius.smAll,
                  onTap: () => controller.setMode(mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: current == mode
                          ? scheme.surface
                          : Colors.transparent,
                      borderRadius: AppRadius.smAll,
                      border: current == mode
                          ? Border.all(color: scheme.outlineVariant)
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 14,
                          color: current == mode
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: current == mode
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: current == mode
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Safe admin avatar that paints the network image via [foregroundImage] so
/// fallback initials never render on top of a loaded photo.
class AdminUserAvatar extends StatelessWidget {
  const AdminUserAvatar({
    super.key,
    required this.avatarUrl,
    required this.displayName,
    this.radius = 18,
  });

  final String? avatarUrl;
  final String displayName;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cleanUrl = avatarUrl?.trim() ?? '';
    final hasAvatar = cleanUrl.isNotEmpty;

    final initials = displayName.trim().isEmpty
        ? 'A'
        : displayName
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .take(2)
              .map((w) => w[0].toUpperCase())
              .join();

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: hasAvatar ? NetworkImage(cleanUrl) : null,
      onForegroundImageError: hasAvatar ? (_, __) {} : null,
      child: Text(
        initials,
        style: theme.textTheme.labelLarge?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
