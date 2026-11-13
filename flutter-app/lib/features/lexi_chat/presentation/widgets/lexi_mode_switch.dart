import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

enum LexiMode { chat, topics }

/// Free chat / topic conversation switch for the Lexi tab, in the app's
/// tactile style. Sits inside the chat header, so it must stay one row high.
class LexiModeSwitch extends StatelessWidget {
  final LexiMode value;
  final ValueChanged<LexiMode> onChanged;

  const LexiModeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tactile =
        theme.extension<AppTactileTheme>() ?? AppTactileTheme.from(theme);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(height / 2);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: tactile.decoration(
        variant: TactileSurfaceVariant.nested,
        fill: scheme.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow headers (four chat actions on a 375px phone) keep the icons
          // and hand the label to Semantics instead.
          final showLabels = constraints.maxWidth >= 160;
          return Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: constraints.maxWidth / 2,
                child: AnimatedSlide(
                  offset: Offset(value.index.toDouble(), 0),
                  duration: motion,
                  curve: Curves.easeOutCubic,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: radius,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final mode in LexiMode.values)
                    Expanded(
                      child: _Segment(
                        mode: mode,
                        selected: mode == value,
                        showLabel: showLabels,
                        radius: radius,
                        onTap: () => onChanged(mode),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final LexiMode mode;
  final bool selected;
  final bool showLabel;
  final BorderRadius radius;
  final VoidCallback onTap;

  const _Segment({
    required this.mode,
    required this.selected,
    required this.showLabel,
    required this.radius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (mode) {
      LexiMode.chat => 'lexiChat.modeFree'.tr(),
      LexiMode.topics => 'lexiChat.modeTopics'.tr(),
    };
    final icon = switch (mode) {
      LexiMode.chat => PhosphorIconsRegular.sparkle,
      LexiMode.topics => PhosphorIconsRegular.chatCircleDots,
    };
    final foreground = selected ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: showLabel ? null : label,
      child: InkWell(
        borderRadius: radius,
        onTap: selected ? null : onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              if (showLabel) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
