import 'dart:math' as math;

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

  /// 0..1 override for how much of the labels to show. The hub drives this
  /// while the switch morphs between its narrow and wide slots, so the labels
  /// grow in instead of popping at the width threshold.
  final double? labelReveal;

  const LexiModeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelReveal,
  });

  static const double labelMinWidth = 160;

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
        : const Duration(milliseconds: 380);

    return Stack(
      children: [
        _track(context, tactile, scheme, radius, motion),
        // The segments sit inside the track's border and padding, which left
        // them 35 px tall; these take the tap over the full 44.
        Positioned.fill(
          child: Row(
            children: [
              for (final mode in LexiMode.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: mode == value,
                    label: _label(mode),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: mode == value ? null : () => onChanged(mode),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // The pill stretches toward its target and settles back to half width, so
  // it reads as flowing across instead of teleporting. Symmetric easing: an
  // ease-out spends most of its distance in the first frames.
  Widget _thumb(
    double trackWidth,
    ColorScheme scheme,
    BorderRadius radius,
    Duration motion,
  ) {
    final half = trackWidth / 2;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.index.toDouble()),
      duration: motion,
      curve: Curves.easeInOutCubic,
      builder: (context, p, _) {
        final width = half * (1 + 0.3 * math.sin(math.pi * p.clamp(0.0, 1.0)));
        return Positioned(
          key: const ValueKey('lexi-mode-thumb'),
          left: p * (trackWidth - width),
          top: 0,
          bottom: 0,
          width: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: radius,
            ),
          ),
        );
      },
    );
  }

  static String _label(LexiMode mode) => switch (mode) {
    LexiMode.chat => 'lexiChat.modeFree'.tr(),
    LexiMode.topics => 'lexiChat.modeTopics'.tr(),
  };

  Widget _track(
    BuildContext context,
    AppTactileTheme tactile,
    ColorScheme scheme,
    BorderRadius radius,
    Duration motion,
  ) {
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
          final reveal =
              labelReveal ??
              (constraints.maxWidth >= labelMinWidth ? 1.0 : 0.0);
          return Stack(
            children: [
              _thumb(constraints.maxWidth, scheme, radius, motion),
              Row(
                children: [
                  for (final mode in LexiMode.values)
                    Expanded(
                      child: _Segment(
                        mode: mode,
                        selected: mode == value,
                        labelReveal: reveal,
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
  final double labelReveal;

  const _Segment({
    required this.mode,
    required this.selected,
    required this.labelReveal,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (mode) {
      LexiMode.chat => PhosphorIconsRegular.sparkle,
      LexiMode.topics => PhosphorIconsRegular.chatCircleDots,
    };
    final foreground = selected ? scheme.onPrimary : scheme.onSurfaceVariant;

    return ExcludeSemantics(
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            if (labelReveal > 0)
              Flexible(
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: labelReveal,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        LexiModeSwitch._label(mode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground.withValues(alpha: labelReveal),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
