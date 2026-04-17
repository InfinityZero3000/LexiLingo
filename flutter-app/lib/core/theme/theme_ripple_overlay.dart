import 'dart:math' as math;
import 'dart:ui' as ui;

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
      duration: const Duration(milliseconds: 700),
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
            if (_controller.isAnimating || _controller.value > 0)
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
    if (progress <= 0) return;

    final maxRadius = _farthestDistance(origin, size) * 1.1;
    final baseRadius = ui.lerpDouble(0, maxRadius, progress) ?? 0;

    final fillPaint = Paint()
      ..color = color.withValues(
        alpha: (0.24 - (progress * 0.16)).clamp(0.0, 0.24),
      )
      ..style = PaintingStyle.fill;

    canvas.drawCircle(origin, baseRadius, fillPaint);

    final ring1 = Paint()
      ..color = color.withValues(
        alpha: (0.35 - (progress * 0.30)).clamp(0.0, 0.35),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = ui.lerpDouble(16, 2, progress) ?? 4;
    final ring2 = Paint()
      ..color = color.withValues(
        alpha: (0.24 - (progress * 0.20)).clamp(0.0, 0.24),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = ui.lerpDouble(10, 1.5, progress) ?? 3;

    canvas.drawCircle(origin, baseRadius * 0.78, ring1);
    canvas.drawCircle(origin, baseRadius * 0.52, ring2);
  }

  double _farthestDistance(Offset origin, Size size) {
    final corners = <Offset>[
      const Offset(0, 0),
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];

    return corners
        .map((corner) => (corner - origin).distance)
        .fold<double>(0, math.max);
  }

  @override
  bool shouldRepaint(covariant _ThemeRipplePainter oldDelegate) {
    return oldDelegate.origin != origin ||
        oldDelegate.color != color ||
        oldDelegate.progress != progress;
  }
}
