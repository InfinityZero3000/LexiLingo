import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthGradientBackground
//
// • login-background.svg  — static full-cover background
// • Floating sparkle particles layered on top for depth
// ─────────────────────────────────────────────────────────────────────────────
class AuthGradientBackground extends StatefulWidget {
  final Widget child;

  const AuthGradientBackground({super.key, required this.child});

  @override
  State<AuthGradientBackground> createState() => _AuthGradientBackgroundState();
}

class _AuthGradientBackgroundState extends State<AuthGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _particleCtrl;
  late final List<_Particle>     _particles;

  @override
  void initState() {
    super.initState();

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    final rng = math.Random(42);
    _particles = List.generate(18, (i) => _Particle.random(rng, i));
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── 1. Static background ─────────────────────────────────────────
        Image.asset(
          'assets/login/login-background.png',
          fit: BoxFit.cover,
        ),

        // ── 2. Floating sparkle particles ─────────────────────────────────────
        AnimatedBuilder(
          animation: _particleCtrl,
          builder: (_, __) {
            return Stack(
              children: _particles.map((p) {
                final t = (_particleCtrl.value + p.phaseOffset) % 1.0;
                final x = p.startX * size.width;
                final y = p.startY * size.height - t * p.travel * size.height;
                final opacity = _particleOpacity(t);

                return Positioned(
                  left: x +
                      math.sin(t * 2 * math.pi * p.swayFreq) * p.swayAmp,
                  top: y,
                  child: Opacity(
                    opacity: opacity,
                    child: _ParticleWidget(particle: p),
                  ),
                );
              }).toList(),
            );
          },
        ),

        // ── 3. Page content ──────────────────────────────────────────────────
        widget.child,
      ],
    );
  }

  /// Fade-in at bottom, hold, fade-out near top
  double _particleOpacity(double t) {
    if (t < 0.15) return t / 0.15;
    if (t > 0.85) return (1.0 - t) / 0.15;
    return 1.0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Particle data + widget
// ─────────────────────────────────────────────────────────────────────────────
class _Particle {
  final double startX;     // 0-1 relative to screen width
  final double startY;     // start Y (0-1 from top – we start near bottom)
  final double travel;     // fraction of screen height to travel upward
  final double size;
  final double phaseOffset;
  final double swayAmp;    // horizontal sway pixels
  final double swayFreq;   // sway cycles per loop
  final Color color;

  const _Particle({
    required this.startX,
    required this.startY,
    required this.travel,
    required this.size,
    required this.phaseOffset,
    required this.swayAmp,
    required this.swayFreq,
    required this.color,
  });

  factory _Particle.random(math.Random rng, int index) {
    final colors = const [
      Color(0xFFFFD700), // gold
      Color(0xFF80DEEA), // cyan
      Color(0xFFA5D6A7), // mint
      Color(0xFFCE93D8), // lavender
      Color(0xFFFFAB91), // peach
      Color(0xFFE6EE9C), // lime
    ];
    return _Particle(
      startX: rng.nextDouble(),
      startY: 0.8 + rng.nextDouble() * 0.35, // start in lower portion
      travel: 0.45 + rng.nextDouble() * 0.4,
      size: 4.0 + rng.nextDouble() * 7.0,
      phaseOffset: rng.nextDouble(),
      swayAmp: 8.0 + rng.nextDouble() * 20.0,
      swayFreq: 0.5 + rng.nextDouble() * 1.5,
      color: colors[index % colors.length],
    );
  }
}

class _ParticleWidget extends StatelessWidget {
  final _Particle particle;

  const _ParticleWidget({required this.particle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: particle.size,
      height: particle.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: particle.color.withValues(alpha: 0.65),
        boxShadow: [
          BoxShadow(
            color: particle.color.withValues(alpha: 0.4),
            blurRadius: particle.size * 1.5,
            spreadRadius: particle.size * 0.3,
          ),
        ],
      ),
    );
  }
}

/// Hero page transition for smooth navigation between auth pages
class AuthPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final String? heroTag;

  AuthPageRoute({required this.page, this.heroTag})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Fade + Scale transition
          final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );

          final scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );

          final slideAnimation =
              Tween<Offset>(
                begin: const Offset(0.0, 0.1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );

          return FadeTransition(
            opacity: fadeAnimation,
            child: ScaleTransition(
              scale: scaleAnimation,
              child: SlideTransition(position: slideAnimation, child: child),
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 400),
      );
}

/// Glassmorphism card for auth forms
class GlassmorphicAuthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double borderRadius;

  const GlassmorphicAuthCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: child,
    );
  }
}
