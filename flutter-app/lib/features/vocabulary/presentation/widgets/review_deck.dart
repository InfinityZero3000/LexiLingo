import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// The current flashcard on top of a fanned pile of the ones still to come.
///
/// [exit] runs 0→1 while the top card is thrown off to the left; the pile
/// moves up one place over the same span, so the next word is already in
/// position when the session swaps it in.
class ReviewDeck extends StatelessWidget {
  const ReviewDeck({
    super.key,
    required this.child,
    required this.behind,
    required this.exit,
    this.cardHeight = 380,
  });

  final Widget child;

  /// Cards left after the current one; at most [maxBehind] are drawn.
  final int behind;
  final Animation<double> exit;
  final double cardHeight;

  static const int maxBehind = 2;

  // Resting pose per depth: angle (radians), downward shift, scale.
  static const _poses = <(double, double, double)>[
    (0, 0, 1),
    (0.09, 6, 1),
    (-0.07, 12, 1),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark
        ? AppColors.surfaceDarkMuted
        : theme.colorScheme.surface;
    final accent = AppColorRoles.primary(isDark);
    final layers = behind.clamp(0, maxBehind);

    Color layerColor(int depth) => Color.alphaBlend(
      accent.withValues(alpha: (isDark ? 0.14 : 0.13) * depth),
      surface,
    );

    Widget layer(int depth, String id) => ExcludeSemantics(
      child: Material(
        key: ValueKey('deck-layer-$id'),
        color: layerColor(depth),
        elevation: 1,
        shadowColor: Colors.black12,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(width: double.infinity, height: cardHeight),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: exit,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(exit.value);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // More cards than the pile shows: one stays put at the bottom
              // so the pile does not thin out while it moves up.
              if (behind > maxBehind)
                _pose(
                  from: _poses[maxBehind],
                  to: _poses[maxBehind],
                  t: t,
                  child: layer(maxBehind, 'rest'),
                ),
              for (var depth = layers; depth >= 1; depth--)
                _pose(
                  from: _poses[depth],
                  to: _poses[depth - 1],
                  t: t,
                  child: layer(depth, '$depth'),
                ),
              Transform.translate(
                offset: Offset(-1.3 * box.maxWidth * exit.value, 0),
                child: Transform.rotate(
                  angle: -0.22 * exit.value,
                  child: Opacity(
                    opacity: 1 - exit.value * 0.4,
                    child: _FaceReveal(
                      key: child.key,
                      cover: layerColor(1),
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pose({
    required (double, double, double) from,
    required (double, double, double) to,
    required double t,
    required Widget child,
  }) => Transform.translate(
    offset: Offset(0, lerpDouble(from.$2, to.$2, t)!),
    child: Transform.rotate(
      angle: lerpDouble(from.$1, to.$1, t)!,
      child: Transform.scale(
        scale: lerpDouble(from.$3, to.$3, t)!,
        child: child,
      ),
    ),
  );
}

/// A new card arrives where a blank pile layer has just settled, so it starts
/// covered in that layer's colour and the cover fades: the layer turns into
/// the card instead of the card popping in over it.
class _FaceReveal extends StatelessWidget {
  const _FaceReveal({super.key, required this.cover, required this.child});

  final Color cover;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              builder: (context, value, _) => value == 0
                  ? const SizedBox.shrink()
                  : Opacity(
                      opacity: value,
                      child: Material(
                        color: cover,
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
