import 'dart:ui';
import 'package:flutter/material.dart';

/// Glassmorphic Card Widget
/// Creates a frosted glass effect card with blur and gradient border
class GlassmorphicCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final double blur;
  final double opacity;
  final Color? borderColor;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final List<Color>? gradientColors;
  final Alignment gradientBegin;
  final Alignment gradientEnd;

  const GlassmorphicCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.blur = 10,
    this.opacity = 0.1,
    this.borderColor,
    this.borderWidth = 1.5,
    this.padding,
    this.margin,
    this.gradientColors,
    this.gradientBegin = Alignment.topLeft,
    this.gradientEnd = Alignment.bottomRight,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.5);
    final bgOpacity = isDark ? opacity * 1.5 : opacity;

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              gradient: LinearGradient(
                begin: gradientBegin,
                end: gradientEnd,
                colors: gradientColors ??
                    [
                      Colors.white.withOpacity(bgOpacity),
                      Colors.white.withOpacity(bgOpacity * 0.5),
                    ],
              ),
              border: Border.all(
                color: borderColor ?? defaultBorderColor,
                width: borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Animated Progress Ring Widget
/// Circular progress indicator with smooth animation
class AnimatedProgressRing extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final double size;
  final double strokeWidth;
  final Color? progressColor;
  final Color? backgroundColor;
  final Widget? child;
  final Duration duration;
  final List<Color>? gradientColors;

  const AnimatedProgressRing({
    super.key,
    required this.progress,
    this.size = 100,
    this.strokeWidth = 8,
    this.progressColor,
    this.backgroundColor,
    this.child,
    this.duration = const Duration(milliseconds: 1000),
    this.gradientColors,
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
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: 0, end: widget.progress).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _previousProgress = _animation.value;
      _animation = Tween<double>(
        begin: _previousProgress,
        end: widget.progress,
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
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
    final primaryColor = widget.progressColor ?? Theme.of(context).primaryColor;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _ProgressRingPainter(
            progress: _animation.value,
            strokeWidth: widget.strokeWidth,
            progressColor: primaryColor,
            backgroundColor:
                widget.backgroundColor ?? Colors.grey.withValues(alpha: 0.2),
            gradientColors: widget.gradientColors,
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
  final List<Color>? gradientColors;

  _ProgressRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.progressColor,
    required this.backgroundColor,
    this.gradientColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background ring
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress ring
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (gradientColors != null && gradientColors!.length >= 2) {
      progressPaint.shader = SweepGradient(
        startAngle: -1.5708, // -90 degrees
        endAngle: 4.7124, // 270 degrees
        colors: gradientColors!,
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    } else {
      progressPaint.color = progressColor;
    }

    final sweepAngle = 2 * 3.14159 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // Start from top (-90 degrees)
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Streak Flame Widget
/// Animated flame icon for streak display
class StreakFlame extends StatefulWidget {
  final int streakCount;
  final double size;
  final bool isActive;

  const StreakFlame({
    super.key,
    required this.streakCount,
    this.size = 48,
    this.isActive = true,
  });

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant StreakFlame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && _controller.isAnimating) {
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
        return Transform.scale(
          scale: widget.isActive ? _scaleAnimation.value : 1.0,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: Colors.orange.withOpacity(_glowAnimation.value),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.local_fire_department,
                  size: widget.size,
                  color: widget.isActive ? Colors.orange : Colors.grey,
                ),
                Positioned(
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.isActive
                          ? Colors.orange.shade700
                          : Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.streakCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shimmer Loading Widget
/// Creates a shimmer effect for loading states
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final bool isLoading;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerLoading({
    super.key,
    required this.child,
    this.isLoading = true,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) return widget.child;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = widget.baseColor ??
        (isDark ? Colors.grey.shade800 : Colors.grey.shade300);
    final highlightColor = widget.highlightColor ??
        (isDark ? Colors.grey.shade700 : Colors.grey.shade100);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                0.0,
                0.5 + _animation.value * 0.25,
                1.0,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

/// Stat Card with Gradient
/// Beautiful stat display card with icon and value
class GradientStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final List<Color> gradientColors;
  final VoidCallback? onTap;

  const GradientStatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    required this.gradientColors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              gradientColors[0].withValues(alpha: 0.15),
              gradientColors[1].withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: gradientColors[0].withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: gradientColors[0],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bento Grid Item
/// Flexible grid item for bento-style layouts
class BentoGridItem extends StatelessWidget {
  final Widget child;
  final int columnSpan;
  final int rowSpan;
  final Color? backgroundColor;
  final List<Color>? gradientColors;
  final double borderRadius;
  final VoidCallback? onTap;

  const BentoGridItem({
    super.key,
    required this.child,
    this.columnSpan = 1,
    this.rowSpan = 1,
    this.backgroundColor,
    this.gradientColors,
    this.borderRadius = 16,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: gradientColors == null ? backgroundColor : null,
          gradient: gradientColors != null
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors!,
                )
              : null,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: child,
        ),
      ),
    );
  }
}
