import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Minimalist animated typing indicator showing Lexi is "thinking".
/// Three subtle bouncing dots with clean design.
class LexiTypingIndicator extends StatefulWidget {
  final bool isThinking;

  const LexiTypingIndicator({super.key, this.isThinking = false});

  @override
  State<LexiTypingIndicator> createState() => _LexiTypingIndicatorState();
}

class _LexiTypingIndicatorState extends State<LexiTypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..repeat(reverse: true);
    });

    // Stagger the start
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 180), () {
        if (mounted) _controllers[i].forward();
      });
    }

    _animations = _controllers.map((c) {
      return Tween<double>(
        begin: 0,
        end: -6,
      ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut));
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
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
                  widget.isThinking ? 'Lexi is thinking' : 'Lexi is typing',
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
                    animation: _animations[i],
                    builder: (_, child) {
                      return Transform.translate(
                        offset: Offset(0, _animations[i].value),
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
