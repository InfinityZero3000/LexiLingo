import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Beautiful empty notification state widget with animated bell illustration
/// Modern design with floating particles and smooth animations
class EmptyNotificationWidget extends StatefulWidget {
  final String title;
  final String description;
  final String? buttonText;
  final VoidCallback? onRefresh;

  const EmptyNotificationWidget({
    super.key,
    this.title = 'No Notifications Yet',
    this.description = 'You\'ll see notifications about your learning progress, achievements, and reminders here.',
    this.buttonText = 'Refresh',
    this.onRefresh,
  });

  @override
  State<EmptyNotificationWidget> createState() => _EmptyNotificationWidgetState();
}

class _EmptyNotificationWidgetState extends State<EmptyNotificationWidget>
    with TickerProviderStateMixin {
  late AnimationController _bellController;
  late AnimationController _pulseController;
  late AnimationController _particleController;
  
  late Animation<double> _bellSwing;
  late Animation<double> _bellScale;
  late Animation<double> _pulseAnimation;
  late Animation<double> _particleAnimation;

  @override
  void initState() {
    super.initState();
    
    // Bell swing animation
    _bellController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);

    _bellSwing = Tween<double>(begin: -0.08, end: 0.08).animate(
      CurvedAnimation(parent: _bellController, curve: Curves.easeInOutSine),
    );
    
    _bellScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.03), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.03, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _bellController, curve: Curves.easeInOut));

    // Pulse animation for glow effect
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Particle floating animation
    _particleController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
    
    _particleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_particleController);
  }

  @override
  void dispose() {
    _bellController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildIllustration(context, isDark),
            const SizedBox(height: 40),
            _buildTitle(context, isDark),
            const SizedBox(height: 16),
            _buildDescription(context, isDark),
            if (widget.buttonText != null && widget.onRefresh != null) ...[
              const SizedBox(height: 36),
              _buildRefreshButton(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIllustration(BuildContext context, bool isDark) {
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated floating particles
          AnimatedBuilder(
            animation: _particleAnimation,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(300, 300),
                painter: _ParticlesPainter(
                  progress: _particleAnimation.value,
                  isDark: isDark,
                ),
              );
            },
          ),
          
          // Pulsing glow background
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 200 + (_pulseAnimation.value * 20),
                height: 200 + (_pulseAnimation.value * 20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.08 * _pulseAnimation.value),
                      AppColors.primary.withValues(alpha: 0.04 * _pulseAnimation.value),
                      Colors.transparent,
                    ],
                    stops: const [0.2, 0.6, 1.0],
                  ),
                ),
              );
            },
          ),
          
          // Inner glow circle
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  (isDark ? Colors.white : AppColors.primary).withValues(alpha: 0.06),
                  Colors.transparent,
                ],
                stops: const [0.5, 1.0],
              ),
            ),
          ),
          
          // Decorative rings
          _buildDecorativeRings(isDark),
          
          // Main bell with animation
          AnimatedBuilder(
            animation: _bellController,
            builder: (context, child) {
              return Transform.scale(
                scale: _bellScale.value,
                child: Transform.rotate(
                  angle: _bellSwing.value,
                  alignment: Alignment.topCenter,
                  child: child,
                ),
              );
            },
            child: _buildModernBell(isDark),
          ),
          
          // Floating decorative elements
          ..._buildFloatingElements(isDark),
        ],
      ),
    );
  }

  Widget _buildDecorativeRings(bool isDark) {
    final baseColor = isDark ? Colors.white : AppColors.primary;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer dashed ring
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: baseColor.withValues(alpha: 0.08),
              width: 1.5,
            ),
          ),
        ),
        // Middle dotted ring
        SizedBox(
          width: 200,
          height: 200,
          child: CustomPaint(
            painter: _DottedCirclePainter(
              color: baseColor.withValues(alpha: 0.12),
              dotCount: 24,
              dotRadius: 2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernBell(bool isDark) {
    return SizedBox(
      width: 140,
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Bell shadow
          Positioned(
            bottom: 5,
            child: Container(
              width: 80,
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: (isDark ? Colors.black : AppColors.primary).withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
          ),
          
          // Main bell body
          CustomPaint(
            size: const Size(140, 170),
            painter: _ModernBellPainter(isDark: isDark),
          ),
          
          // Bell highlight
          Positioned(
            top: 50,
            left: 35,
            child: Container(
              width: 25,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.4),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          
          // Notification badge (empty indicator)
          Positioned(
            top: 30,
            right: 25,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                border: Border.all(
                  color: isDark ? Colors.grey[800]! : Colors.white,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  '0',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[500],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFloatingElements(bool isDark) {
    final primaryColor = isDark ? const Color(0xFF64B5F6) : AppColors.primary;
    final accentColor = isDark ? const Color(0xFFFFD54F) : AppColors.accentYellow;
    
    return [
      // Sparkle stars
      Positioned(
        top: 35,
        right: 40,
        child: _buildSparkle(primaryColor, 18),
      ),
      Positioned(
        top: 70,
        left: 25,
        child: _buildSparkle(accentColor, 14),
      ),
      Positioned(
        bottom: 50,
        right: 30,
        child: _buildSparkle(primaryColor.withValues(alpha: 0.7), 12),
      ),
      Positioned(
        bottom: 80,
        left: 35,
        child: _buildSparkle(accentColor.withValues(alpha: 0.8), 16),
      ),
      
      // Floating dots
      Positioned(
        top: 55,
        left: 55,
        child: _buildFloatingDot(8, primaryColor.withValues(alpha: 0.5)),
      ),
      Positioned(
        top: 100,
        right: 20,
        child: _buildFloatingDot(6, accentColor.withValues(alpha: 0.6)),
      ),
      Positioned(
        bottom: 100,
        left: 20,
        child: _buildFloatingDot(10, primaryColor.withValues(alpha: 0.4)),
      ),
      Positioned(
        bottom: 60,
        right: 55,
        child: _buildFloatingDot(5, accentColor.withValues(alpha: 0.5)),
      ),
      
      // Small circles
      Positioned(
        top: 120,
        left: 15,
        child: _buildOutlineCircle(14, primaryColor.withValues(alpha: 0.3)),
      ),
      Positioned(
        bottom: 120,
        right: 18,
        child: _buildOutlineCircle(12, accentColor.withValues(alpha: 0.4)),
      ),
    ];
  }

  Widget _buildSparkle(Color color, double size) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: 0.8 + (_pulseAnimation.value * 0.4),
          child: Opacity(
            opacity: 0.6 + (_pulseAnimation.value * 0.4),
            child: CustomPaint(
              size: Size(size, size),
              painter: _SparklePainter(color: color),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingDot(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: size,
            spreadRadius: size / 4,
          ),
        ],
      ),
    );
  }

  Widget _buildOutlineCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, bool isDark) {
    return Text(
      widget.title,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
            letterSpacing: -0.5,
          ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildDescription(BuildContext context, bool isDark) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Text(
        widget.description,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              height: 1.6,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRefreshButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: widget.onRefresh,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 20),
            const SizedBox(width: 8),
            Text(
              widget.buttonText!,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modern bell painter with gradient and smooth curves
class _ModernBellPainter extends CustomPainter {
  final bool isDark;
  
  _ModernBellPainter({this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    
    // Bell colors based on theme
    final bellGradient = isDark
        ? [
            const Color(0xFF4A5568),
            const Color(0xFF2D3748),
            const Color(0xFF1A202C),
          ]
        : [
            const Color(0xFFE8F4FD),
            const Color(0xFFB8D4F0),
            const Color(0xFF90C2E7),
          ];

    // Bell body paint
    final bellPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: bellGradient,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Bell handle
    final handlePaint = Paint()
      ..color = isDark ? const Color(0xFF4A5568) : const Color(0xFF90C2E7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Draw handle arc
    final handleRect = Rect.fromCenter(
      center: Offset(centerX, 12),
      width: 24,
      height: 24,
    );
    canvas.drawArc(handleRect, math.pi, math.pi, false, handlePaint);

    // Bell body path
    final bellPath = Path();
    
    // Start from top center, below handle
    bellPath.moveTo(centerX, 20);
    
    // Left curve of bell dome
    bellPath.cubicTo(
      size.width * 0.2, 25,
      size.width * 0.1, size.height * 0.3,
      size.width * 0.12, size.height * 0.55,
    );
    
    // Left bottom curve
    bellPath.cubicTo(
      size.width * 0.08, size.height * 0.75,
      size.width * 0.05, size.height * 0.85,
      0, size.height * 0.82,
    );
    
    // Bottom left edge
    bellPath.lineTo(0, size.height * 0.85);
    
    // Bottom curve
    bellPath.quadraticBezierTo(
      centerX, size.height * 0.92,
      size.width, size.height * 0.85,
    );
    
    // Right bottom edge
    bellPath.lineTo(size.width, size.height * 0.82);
    
    // Right bottom curve
    bellPath.cubicTo(
      size.width * 0.95, size.height * 0.85,
      size.width * 0.92, size.height * 0.75,
      size.width * 0.88, size.height * 0.55,
    );
    
    // Right curve of bell dome
    bellPath.cubicTo(
      size.width * 0.9, size.height * 0.3,
      size.width * 0.8, 25,
      centerX, 20,
    );
    
    bellPath.close();
    
    canvas.drawPath(bellPath, bellPaint);

    // Bell clapper
    final clapperPaint = Paint()
      ..color = isDark ? const Color(0xFF718096) : const Color(0xFF64B5F6)
      ..style = PaintingStyle.fill;
    
    // Clapper string
    canvas.drawLine(
      Offset(centerX, size.height * 0.75),
      Offset(centerX, size.height * 0.92),
      Paint()
        ..color = isDark ? const Color(0xFF4A5568) : const Color(0xFF90C2E7)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    
    // Clapper ball
    canvas.drawCircle(
      Offset(centerX, size.height * 0.95),
      8,
      clapperPaint,
    );
    
    // Clapper highlight
    canvas.drawCircle(
      Offset(centerX - 2, size.height * 0.93),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Sparkle/star painter
class _SparklePainter extends CustomPainter {
  final Color color;
  
  _SparklePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final path = Path();
    
    // 4-pointed star with smooth curves
    final outerRadius = size.width / 2;
    final innerRadius = size.width * 0.15;
    
    for (int i = 0; i < 4; i++) {
      final outerAngle = (i * math.pi / 2) - math.pi / 2;
      final innerAngle = outerAngle + math.pi / 4;
      
      final outerX = center.dx + outerRadius * math.cos(outerAngle);
      final outerY = center.dy + outerRadius * math.sin(outerAngle);
      final innerX = center.dx + innerRadius * math.cos(innerAngle);
      final innerY = center.dy + innerRadius * math.sin(innerAngle);
      
      if (i == 0) {
        path.moveTo(outerX, outerY);
      } else {
        path.lineTo(outerX, outerY);
      }
      path.lineTo(innerX, innerY);
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Dotted circle painter
class _DottedCirclePainter extends CustomPainter {
  final Color color;
  final int dotCount;
  final double dotRadius;
  
  _DottedCirclePainter({
    required this.color,
    this.dotCount = 20,
    this.dotRadius = 2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - dotRadius;
    
    for (int i = 0; i < dotCount; i++) {
      final angle = (2 * math.pi * i) / dotCount;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      canvas.drawCircle(Offset(x, y), dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Floating particles painter
class _ParticlesPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  
  _ParticlesPainter({required this.progress, this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42); // Fixed seed for consistent particles
    final baseColor = isDark ? Colors.white : AppColors.primary;
    
    for (int i = 0; i < 15; i++) {
      final startX = random.nextDouble() * size.width;
      final startY = random.nextDouble() * size.height;
      final radius = 1.0 + random.nextDouble() * 2;
      final speed = 0.5 + random.nextDouble() * 0.5;
      final phase = random.nextDouble() * 2 * math.pi;
      
      // Calculate animated position
      final animatedProgress = (progress * speed + phase / (2 * math.pi)) % 1.0;
      final y = startY + (animatedProgress * 60 - 30);
      final x = startX + math.sin(animatedProgress * 2 * math.pi + phase) * 15;
      
      // Fade based on vertical position
      final opacity = (0.15 + (1 - (y / size.height).abs()) * 0.25).clamp(0.0, 0.4);
      
      final paint = Paint()
        ..color = baseColor.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      
      if (y >= 0 && y <= size.height && x >= 0 && x <= size.width) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
