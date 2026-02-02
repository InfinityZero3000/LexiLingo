import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated Star Rating
/// Beautiful animated star rating component
class AnimatedStarRating extends StatefulWidget {
  final double rating;
  final int starCount;
  final double size;
  final Color filledColor;
  final Color unfilledColor;
  final Duration animationDuration;

  const AnimatedStarRating({
    super.key,
    required this.rating,
    this.starCount = 5,
    this.size = 24,
    this.filledColor = Colors.amber,
    this.unfilledColor = Colors.grey,
    this.animationDuration = const Duration(milliseconds: 500),
  });

  @override
  State<AnimatedStarRating> createState() => _AnimatedStarRatingState();
}

class _AnimatedStarRatingState extends State<AnimatedStarRating>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: widget.rating).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedStarRating oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rating != widget.rating) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.rating,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.starCount, (index) {
            final fillAmount = (_animation.value - index).clamp(0.0, 1.0);
            
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: Duration(milliseconds: 200 + (index * 100)),
              curve: Curves.elasticOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: fillAmount > 0 ? scale : 0.8,
                  child: _StarIcon(
                    size: widget.size,
                    fillAmount: fillAmount,
                    filledColor: widget.filledColor,
                    unfilledColor: widget.unfilledColor,
                  ),
                );
              },
            );
          }),
        );
      },
    );
  }
}

class _StarIcon extends StatelessWidget {
  final double size;
  final double fillAmount;
  final Color filledColor;
  final Color unfilledColor;

  const _StarIcon({
    required this.size,
    required this.fillAmount,
    required this.filledColor,
    required this.unfilledColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StarPainter(
          fillAmount: fillAmount,
          filledColor: filledColor,
          unfilledColor: unfilledColor,
        ),
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  final double fillAmount;
  final Color filledColor;
  final Color unfilledColor;

  _StarPainter({
    required this.fillAmount,
    required this.filledColor,
    required this.unfilledColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius * 0.4;

    final path = _createStarPath(center, outerRadius, innerRadius, 5);

    // Draw unfilled star
    final unfilledPaint = Paint()
      ..color = unfilledColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, unfilledPaint);

    // Draw filled portion
    if (fillAmount > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * fillAmount, size.height));
      final filledPaint = Paint()
        ..color = filledColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, filledPaint);
      canvas.restore();
    }
  }

  Path _createStarPath(Offset center, double outerRadius, double innerRadius, int points) {
    final path = Path();
    final angle = math.pi / points;

    for (int i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outerRadius : innerRadius;
      final x = center.dx + radius * math.sin(i * angle - math.pi / 2);
      final y = center.dy + radius * math.cos(i * angle - math.pi / 2);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_StarPainter oldDelegate) =>
      oldDelegate.fillAmount != fillAmount ||
      oldDelegate.filledColor != filledColor;
}

/// Spinning Loader
/// A simple yet elegant spinning loader
class SpinningLoader extends StatefulWidget {
  final double size;
  final Color color;
  final double strokeWidth;
  final Duration duration;

  const SpinningLoader({
    super.key,
    this.size = 40,
    this.color = Colors.blue,
    this.strokeWidth = 3,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<SpinningLoader> createState() => _SpinningLoaderState();
}

class _SpinningLoaderState extends State<SpinningLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _SpinningLoaderPainter(
            progress: _controller.value,
            color: widget.color,
            strokeWidth: widget.strokeWidth,
          ),
        );
      },
    );
  }
}

class _SpinningLoaderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _SpinningLoaderPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final startAngle = progress * 2 * math.pi;
    final sweepAngle = 1.2 + 0.6 * math.sin(progress * 2 * math.pi);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpinningLoaderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Bounce Dots Loader
/// Three bouncing dots animation
class BouncingDotsLoader extends StatefulWidget {
  final double dotSize;
  final Color color;
  final double spacing;

  const BouncingDotsLoader({
    super.key,
    this.dotSize = 10,
    this.color = Colors.blue,
    this.spacing = 4,
  });

  @override
  State<BouncingDotsLoader> createState() => _BouncingDotsLoaderState();
}

class _BouncingDotsLoaderState extends State<BouncingDotsLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.2;
            final value = ((_controller.value + delay) % 1.0);
            final bounce = math.sin(value * math.pi);
            
            return Container(
              margin: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
              child: Transform.translate(
                offset: Offset(0, -bounce * widget.dotSize),
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.6 + bounce * 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

/// Heartbeat Animation
/// Pulsing heart animation for likes, favorites
class HeartbeatAnimation extends StatefulWidget {
  final double size;
  final Color color;
  final bool isActive;

  const HeartbeatAnimation({
    super.key,
    this.size = 32,
    this.color = Colors.red,
    this.isActive = true,
  });

  @override
  State<HeartbeatAnimation> createState() => _HeartbeatAnimationState();
}

class _HeartbeatAnimationState extends State<HeartbeatAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(HeartbeatAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (_controller.value * 0.2);
        return Transform.scale(
          scale: scale,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _HeartPainter(color: widget.color),
          ),
        );
      },
    );
  }
}

class _HeartPainter extends CustomPainter {
  final Color color;

  _HeartPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final width = size.width;
    final height = size.height;

    path.moveTo(width / 2, height * 0.85);
    path.cubicTo(
      width * 0.1, height * 0.6,
      width * 0.1, height * 0.2,
      width / 2, height * 0.35,
    );
    path.cubicTo(
      width * 0.9, height * 0.2,
      width * 0.9, height * 0.6,
      width / 2, height * 0.85,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HeartPainter oldDelegate) => oldDelegate.color != color;
}

/// Countdown Timer Animation
/// Animated countdown circle
class CountdownTimer extends StatefulWidget {
  final int seconds;
  final double size;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;
  final VoidCallback? onComplete;
  final TextStyle? textStyle;

  const CountdownTimer({
    super.key,
    required this.seconds,
    this.size = 80,
    this.backgroundColor = Colors.grey,
    this.progressColor = Colors.blue,
    this.strokeWidth = 6,
    this.onComplete,
    this.textStyle,
  });

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.seconds;
    _controller = AnimationController(
      duration: Duration(seconds: widget.seconds),
      vsync: this,
    );
    _controller.addListener(_updateTime);
    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  void _updateTime() {
    final newRemaining = (widget.seconds * (1 - _controller.value)).ceil();
    if (newRemaining != _remainingSeconds) {
      setState(() {
        _remainingSeconds = newRemaining;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateTime);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _CountdownPainter(
                  progress: 1 - _controller.value,
                  backgroundColor: widget.backgroundColor.withValues(alpha: 0.3),
                  progressColor: widget.progressColor,
                  strokeWidth: widget.strokeWidth,
                ),
              ),
              Text(
                '$_remainingSeconds',
                style: widget.textStyle ??
                    TextStyle(
                      fontSize: widget.size * 0.35,
                      fontWeight: FontWeight.bold,
                      color: widget.progressColor,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CountdownPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  _CountdownPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background circle
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CountdownPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Success Burst Animation
/// Celebration burst effect for achievements
class SuccessBurst extends StatefulWidget {
  final double size;
  final Color color;
  final int particleCount;
  final VoidCallback? onComplete;

  const SuccessBurst({
    super.key,
    this.size = 100,
    this.color = Colors.amber,
    this.particleCount = 12,
    this.onComplete,
  });

  @override
  State<SuccessBurst> createState() => _SuccessBurstState();
}

class _SuccessBurstState extends State<SuccessBurst>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _SuccessBurstPainter(
            progress: _controller.value,
            color: widget.color,
            particleCount: widget.particleCount,
          ),
        );
      },
    );
  }
}

class _SuccessBurstPainter extends CustomPainter {
  final double progress;
  final Color color;
  final int particleCount;

  _SuccessBurstPainter({
    required this.progress,
    required this.color,
    required this.particleCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < particleCount; i++) {
      final angle = (i / particleCount) * 2 * math.pi;
      final distance = maxRadius * Curves.easeOut.transform(progress);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final particleSize = 6 * (1 - progress * 0.5);

      final x = center.dx + distance * math.cos(angle);
      final y = center.dy + distance * math.sin(angle);

      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), particleSize, paint);
    }

    // Center glow
    if (progress < 0.5) {
      final glowProgress = progress * 2;
      final glowPaint = Paint()
        ..color = color.withOpacity((1 - glowProgress) * 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        center,
        maxRadius * 0.3 * Curves.easeOut.transform(glowProgress),
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SuccessBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Slide Fade Transition
/// Wrapper widget for slide + fade entrance animation
class SlideFadeTransition extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Offset beginOffset;
  final Curve curve;

  const SlideFadeTransition({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 400),
    this.delay = Duration.zero,
    this.beginOffset = const Offset(0, 20),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<SlideFadeTransition> createState() => _SlideFadeTransitionState();
}

class _SlideFadeTransitionState extends State<SlideFadeTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _slideAnimation = Tween<Offset>(
      begin: widget.beginOffset,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: _slideAnimation.value,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Scale Bounce Transition  
/// Wrapper widget for scale + bounce entrance animation
class ScaleBounceTransition extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double beginScale;

  const ScaleBounceTransition({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.delay = Duration.zero,
    this.beginScale = 0.5,
  });

  @override
  State<ScaleBounceTransition> createState() => _ScaleBounceTransitionState();
}

class _ScaleBounceTransitionState extends State<ScaleBounceTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: widget.beginScale, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: widget.child,
        );
      },
    );
  }
}
