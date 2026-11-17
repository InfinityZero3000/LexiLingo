import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class SectionTitle extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionTitle({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heading = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: AppColorRoles.textPrimary(isDark),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: actionLabel == null || onAction == null
          ? heading
          : Row(
              children: [
                Expanded(child: heading),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: AppColorRoles.primary(isDark),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      actionLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
