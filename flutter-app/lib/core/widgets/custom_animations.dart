import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Collection of lightweight custom animations using CustomPaint
/// These animations are optimized for performance without external dependencies

// ============================================================================
// PULSE ANIMATION - For buttons, icons, notifications
// ============================================================================

/// Animated pulse effect around a widget
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final Color color;
  final double maxRadius;
  final Duration duration;
  final bool enabled;

  const PulseAnimation({
    super.key,
    required this.child,
    this.color = Colors.blue,
    this.maxRadius = 30,
    this.duration = const Duration(milliseconds: 1500),
    this.enabled = true,
  });

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    if (widget.enabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(PulseAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
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
        return CustomPaint(
          painter: _PulsePainter(
            progress: _controller.value,
            color: widget.color,
            maxRadius: widget.maxRadius,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double maxRadius;

  _PulsePainter({
    required this.progress,
    required this.color,
    required this.maxRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = math.min(size.width, size.height) / 2;
    
    // Draw multiple expanding rings
    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + i * 0.33) % 1.0;
      final radius = baseRadius + (maxRadius * ringProgress);
      final opacity = (1.0 - ringProgress) * 0.5;
      
      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - ringProgress);
      
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ============================================================================
// SHIMMER EFFECT - For loading states
// ============================================================================

/// Lightweight shimmer effect without external packages
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;

  const ShimmerEffect({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFE0E0E0),
    this.highlightColor = const Color(0xFFF5F5F5),
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
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
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ].map((s) => s.clamp(0.0, 1.0)).toList(),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ============================================================================
// WAVE ANIMATION - For backgrounds, decorations
// ============================================================================

/// Animated wave background
class WaveAnimation extends StatefulWidget {
  final Color color;
  final double height;
  final int waveCount;
  final Duration duration;

  const WaveAnimation({
    super.key,
    this.color = Colors.blue,
    this.height = 100,
    this.waveCount = 3,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<WaveAnimation> createState() => _WaveAnimationState();
}

class _WaveAnimationState extends State<WaveAnimation>
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
          painter: _WavePainter(
            progress: _controller.value,
            color: widget.color,
            waveCount: widget.waveCount,
          ),
          size: Size(double.infinity, widget.height),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final Color color;
  final int waveCount;

  _WavePainter({
    required this.progress,
    required this.color,
    required this.waveCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < waveCount; i++) {
      final opacity = 0.3 - (i * 0.08);
      final amplitude = size.height * (0.3 - i * 0.05);
      final phaseShift = progress * 2 * math.pi + (i * math.pi / 3);
      
      final paint = Paint()
        ..color = color.withOpacity(opacity.clamp(0.1, 0.3))
        ..style = PaintingStyle.fill;
      
      final path = Path();
      path.moveTo(0, size.height);
      
      for (double x = 0; x <= size.width; x++) {
        final y = size.height * 0.5 +
            amplitude * math.sin((x / size.width * 2 * math.pi) + phaseShift);
        path.lineTo(x, y);
      }
      
      path.lineTo(size.width, size.height);
      path.close();
      
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ============================================================================
// FLOATING PARTICLES - For decorative backgrounds
// ============================================================================

/// Floating particles animation
class FloatingParticles extends StatefulWidget {
  final int particleCount;
  final Color color;
  final double maxSize;

  const FloatingParticles({
    super.key,
    this.particleCount = 20,
    this.color = Colors.white,
    this.maxSize = 8,
  });

  @override
  State<FloatingParticles> createState() => _FloatingParticlesState();
}

class _FloatingParticlesState extends State<FloatingParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();
    
    _particles = List.generate(
      widget.particleCount,
      (_) => _Particle.random(widget.maxSize),
    );
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
          painter: _ParticlesPainter(
            particles: _particles,
            progress: _controller.value,
            color: widget.color,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Particle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });

  factory _Particle.random(double maxSize) {
    final random = math.Random();
    return _Particle(
      x: random.nextDouble(),
      y: random.nextDouble(),
      size: random.nextDouble() * maxSize + 2,
      speed: random.nextDouble() * 0.5 + 0.2,
      opacity: random.nextDouble() * 0.5 + 0.2,
    );
  }
}

class _ParticlesPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color color;

  _ParticlesPainter({
    required this.particles,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final x = particle.x * size.width;
      final y = ((particle.y + progress * particle.speed) % 1.0) * size.height;
      
      final paint = Paint()
        ..color = color.withOpacity(particle.opacity)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(Offset(x, y), particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ============================================================================
// PROGRESS RING - For circular progress indicators
// ============================================================================

/// Animated circular progress indicator
class AnimatedProgressRing extends StatefulWidget {
  final double progress;
  final double size;
  final double strokeWidth;
  final Color progressColor;
  final Color backgroundColor;
  final Widget? child;
  final Duration duration;

  const AnimatedProgressRing({
    super.key,
    required this.progress,
    this.size = 100,
    this.strokeWidth = 8,
    this.progressColor = Colors.blue,
    this.backgroundColor = Colors.grey,
    this.child,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<AnimatedProgressRing> createState() => _AnimatedProgressRingState();
}

class _AnimatedProgressRingState extends State<AnimatedProgressRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(AnimatedProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _previousProgress = oldWidget.progress;
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    _animation = Tween<double>(
      begin: _previousProgress,
      end: widget.progress,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _controller.forward(from: 0);
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
        return CustomPaint(
          painter: _ProgressRingPainter(
            progress: _animation.value,
            strokeWidth: widget.strokeWidth,
            progressColor: widget.progressColor,
            backgroundColor: widget.backgroundColor,
          ),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(child: widget.child),
          ),
        );
      },
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color progressColor;
  final Color backgroundColor;

  _ProgressRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.progressColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    
    // Background circle
    final bgPaint = Paint()
      ..color = backgroundColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    
    canvas.drawCircle(center, radius, bgPaint);
    
    // Progress arc
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    
    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ============================================================================
// RIPPLE EFFECT - For touch feedback
// ============================================================================

/// Ripple effect on tap
class RippleEffect extends StatefulWidget {
  final Widget child;
  final Color rippleColor;
  final VoidCallback? onTap;

  const RippleEffect({
    super.key,
    required this.child,
    this.rippleColor = Colors.white,
    this.onTap,
  });

  @override
  State<RippleEffect> createState() => _RippleEffectState();
}

class _RippleEffectState extends State<RippleEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Offset? _tapPosition;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(TapDownDetails details) {
    setState(() {
      _tapPosition = details.localPosition;
    });
    _controller.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _tapPosition != null
                ? _RipplePainter(
                    progress: _controller.value,
                    center: _tapPosition!,
                    color: widget.rippleColor,
                  )
                : null,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  final Offset center;
  final Color color;

  _RipplePainter({
    required this.progress,
    required this.center,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height);
    final radius = maxRadius * progress;
    final opacity = (1.0 - progress) * 0.3;
    
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ============================================================================
// BREATHING GLOW - For highlighting important elements
// ============================================================================

/// Breathing glow effect
class BreathingGlow extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final double maxBlur;
  final Duration duration;

  const BreathingGlow({
    super.key,
    required this.child,
    this.glowColor = Colors.blue,
    this.maxBlur = 20,
    this.duration = const Duration(milliseconds: 2000),
  });

  @override
  State<BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<BreathingGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat(reverse: true);
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
        final blur = widget.maxBlur * _controller.value;
        return Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(0.3 + 0.3 * _controller.value),
                blurRadius: blur,
                spreadRadius: blur / 4,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ============================================================================
// TYPING INDICATOR - For chat/messaging
// ============================================================================

/// Animated typing indicator dots
class TypingIndicator extends StatefulWidget {
  final Color color;
  final double dotSize;
  final double spacing;

  const TypingIndicator({
    super.key,
    this.color = Colors.grey,
    this.dotSize = 8,
    this.spacing = 4,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _TypingIndicatorPainter(
            progress: _controller.value,
            color: widget.color,
            dotSize: widget.dotSize,
            spacing: widget.spacing,
          ),
          size: Size(
            widget.dotSize * 3 + widget.spacing * 2,
            widget.dotSize * 2,
          ),
        );
      },
    );
  }
}

class _TypingIndicatorPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double dotSize;
  final double spacing;

  _TypingIndicatorPainter({
    required this.progress,
    required this.color,
    required this.dotSize,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 3; i++) {
      final delay = i * 0.2;
      final animProgress = ((progress - delay) % 1.0).clamp(0.0, 1.0);
      final bounce = math.sin(animProgress * math.pi);
      
      final x = dotSize / 2 + i * (dotSize + spacing);
      final y = size.height / 2 - bounce * dotSize / 2;
      
      final paint = Paint()
        ..color = color.withOpacity(0.4 + 0.6 * bounce)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(Offset(x, y), dotSize / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_TypingIndicatorPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ============================================================================
// GRADIENT BORDER - For cards and containers
// ============================================================================

/// Animated gradient border
class AnimatedGradientBorder extends StatefulWidget {
  final Widget child;
  final double borderWidth;
  final double borderRadius;
  final List<Color> colors;
  final Duration duration;

  const AnimatedGradientBorder({
    super.key,
    required this.child,
    this.borderWidth = 2,
    this.borderRadius = 12,
    this.colors = const [Colors.blue, Colors.purple, Colors.pink, Colors.blue],
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<AnimatedGradientBorder> createState() => _AnimatedGradientBorderState();
}

class _AnimatedGradientBorderState extends State<AnimatedGradientBorder>
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
          painter: _GradientBorderPainter(
            progress: _controller.value,
            borderWidth: widget.borderWidth,
            borderRadius: widget.borderRadius,
            colors: widget.colors,
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.borderWidth),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _GradientBorderPainter extends CustomPainter {
  final double progress;
  final double borderWidth;
  final double borderRadius;
  final List<Color> colors;

  _GradientBorderPainter({
    required this.progress,
    required this.borderWidth,
    required this.borderRadius,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      borderWidth / 2,
      borderWidth / 2,
      size.width - borderWidth,
      size.height - borderWidth,
    );
    
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(borderRadius),
    );
    
    final gradient = SweepGradient(
      startAngle: progress * 2 * math.pi,
      colors: colors,
    );
    
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GradientBorderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ============================================================================
// SUCCESS CHECKMARK - For completion feedback
// ============================================================================

/// Animated success checkmark
class AnimatedCheckmark extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;
  final VoidCallback? onComplete;

  const AnimatedCheckmark({
    super.key,
    this.size = 80,
    this.color = Colors.green,
    this.duration = const Duration(milliseconds: 800),
    this.onComplete,
  });

  @override
  State<AnimatedCheckmark> createState() => _AnimatedCheckmarkState();
}

class _AnimatedCheckmarkState extends State<AnimatedCheckmark>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
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
          painter: _CheckmarkPainter(
            progress: _controller.value,
            color: widget.color,
          ),
          size: Size(widget.size, widget.size),
        );
      },
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CheckmarkPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    
    // Circle background
    final circleProgress = (progress * 2).clamp(0.0, 1.0);
    final circlePaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * circleProgress, circlePaint);
    
    // Circle border
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * circleProgress,
      false,
      borderPaint,
    );
    
    // Checkmark
    if (progress > 0.5) {
      final checkProgress = ((progress - 0.5) * 2).clamp(0.0, 1.0);
      final checkPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      
      final path = Path();
      final startX = size.width * 0.28;
      final startY = size.height * 0.52;
      final midX = size.width * 0.45;
      final midY = size.height * 0.68;
      final endX = size.width * 0.75;
      final endY = size.height * 0.35;
      
      path.moveTo(startX, startY);
      
      if (checkProgress <= 0.5) {
        final p = checkProgress * 2;
        path.lineTo(
          startX + (midX - startX) * p,
          startY + (midY - startY) * p,
        );
      } else {
        path.lineTo(midX, midY);
        final p = (checkProgress - 0.5) * 2;
        path.lineTo(
          midX + (endX - midX) * p,
          midY + (endY - midY) * p,
        );
      }
      
      canvas.drawPath(path, checkPaint);
    }
  }

  @override
  bool shouldRepaint(_CheckmarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
