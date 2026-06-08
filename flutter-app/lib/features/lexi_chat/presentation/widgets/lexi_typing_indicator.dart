import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Minimalist animated typing indicator showing Lexi is "thinking".
/// Three subtle bouncing dots with clean design.
class LexiTypingIndicator extends StatefulWidget {
  final bool isThinking;
  final String name;

  const LexiTypingIndicator({
    super.key,
    this.isThinking = false,
    this.name = 'Lexi',
  });

  @override
  State<LexiTypingIndicator> createState() => _LexiTypingIndicatorState();
}

class _LexiTypingIndicatorState extends State<LexiTypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _dotOffsets;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _dotOffsets = List.generate(3, (index) {
      final start = index * 0.16;
      return TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0, end: -5), weight: 45),
        TweenSequenceItem(tween: Tween(begin: -5, end: 0), weight: 55),
      ]).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, start + 0.52, curve: Curves.easeInOutCubic),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? AppColors.surfaceDarkChat
                    : AppColors.chatBgLight,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.isThinking ? '${widget.name} is thinking' : '${widget.name} is typing',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white54 : AppColors.textGrey,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 10),
                ...List.generate(3, (i) {
                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (_, child) {
                      return Transform.translate(
                        offset: Offset(0, _dotOffsets[i].value),
                        child: child,
                      );
                    },
                    child: Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColorRoles.primary(
                                isDark,
                              ).withValues(alpha: 0.7)
                            : AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
