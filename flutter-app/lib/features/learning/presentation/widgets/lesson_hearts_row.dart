import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class LessonHeartsRow extends StatelessWidget {
  const LessonHeartsRow({super.key, required this.lives, this.maxLives = 3});

  final int lives;
  final int maxLives;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final remaining = lives.clamp(0, maxLives);

    return Semantics(
      label: 'lesson.heartsLeft'.tr(namedArgs: {'count': '$remaining'}),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < maxLives; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOut,
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    i < remaining
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    key: ValueKey<bool>(i < remaining),
                    size: 22,
                    color: i < remaining ? scheme.error : scheme.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
