import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/theme_ripple_bus.dart';

class ThemeRippleOverlay extends StatefulWidget {
  final Widget child;

  const ThemeRippleOverlay({super.key, required this.child});

  @override
  State<ThemeRippleOverlay> createState() => _ThemeRippleOverlayState();
}

class _ThemeRippleOverlayState extends State<ThemeRippleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Offset _origin = Offset.zero;
  Color _color = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );

    ThemeRippleBus.instance.notifier.addListener(_handleRippleEvent);
  }

  @override
  void dispose() {
    ThemeRippleBus.instance.notifier.removeListener(_handleRippleEvent);
    _controller.dispose();
    super.dispose();
  }

  void _handleRippleEvent() {
    final event = ThemeRippleBus.instance.notifier.value;
    if (event == null) return;

    setState(() {
      _origin = event.origin;
      _color = event.color;
    });

    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(_controller.value);

        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            if (_controller.isAnimating)
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _ThemeRipplePainter(
                      origin: _origin,
                      color: _color,
                      progress: progress,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class _ThemeRipplePainter extends CustomPainter {
  final Offset origin;
  final Color color;
  final double progress;

  const _ThemeRipplePainter({
    required this.origin,
    required this.color,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    // Use an approximation based on diagonal to keep per-frame cost low.
    final maxRadius = (size.longestSide * math.sqrt2) * 0.95;
    final baseRadius = maxRadius * progress;

    final fillPaint = Paint()
      ..color = color.withValues(
        alpha: (0.20 - (progress * 0.20)).clamp(0.0, 0.20),
      )
      ..style = PaintingStyle.fill;

    canvas.drawCircle(origin, baseRadius, fillPaint);

    // Keep only one thin ring for the wave feel while reducing draw load.
    final ring = Paint()
      ..color = color.withValues(
        alpha: (0.18 - (progress * 0.18)).clamp(0.0, 0.18),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 - (6 * progress);

    canvas.drawCircle(origin, baseRadius * 0.74, ring);
  }

  @override
  bool shouldRepaint(covariant _ThemeRipplePainter oldDelegate) {
    return oldDelegate.origin != origin ||
        oldDelegate.color != color ||
        oldDelegate.progress != progress;
  }
}
