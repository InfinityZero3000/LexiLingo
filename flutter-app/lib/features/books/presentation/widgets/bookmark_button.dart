import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Animated bookmark toggle button for the reader screen.
///
/// Shows a filled bookmark icon when the current page is bookmarked,
/// outlined when not. Pulses briefly on state change.
///
/// Phase 5: Book Reading — skill: ui-ux-pro-max.
class BookmarkButton extends StatefulWidget {
  final bool isBookmarked;
  final VoidCallback onToggle;
  final Color? color;

  const BookmarkButton({
    super.key,
    required this.isBookmarked,
    required this.onToggle,
    this.color,
  });

  @override
  State<BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends State<BookmarkButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(_controller);
  }

  @override
  void didUpdateWidget(BookmarkButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isBookmarked != widget.isBookmarked) {
      _controller.forward().then((_) => _controller.reverse());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.color ?? AppColors.primary;

    return ScaleTransition(
      scale: _scaleAnim,
      child: IconButton(
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            widget.isBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            key: ValueKey(widget.isBookmarked),
            color: widget.isBookmarked ? activeColor : Colors.grey,
          ),
        ),
        tooltip: widget.isBookmarked ? 'Remove bookmark' : 'Add bookmark',
        onPressed: widget.onToggle,
      ),
    );
  }
}
