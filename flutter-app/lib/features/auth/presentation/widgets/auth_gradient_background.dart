import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated gradient background for auth pages (login, welcome)
/// Features a colorful gradient with floating bubbles animation
class AuthGradientBackground extends StatefulWidget {
  final Widget child;

  const AuthGradientBackground({
    super.key,
    required this.child,
  });

  @override
  State<AuthGradientBackground> createState() => _AuthGradientBackgroundState();
}

class _AuthGradientBackgroundState extends State<AuthGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
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
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Color(0xFF4FC3F7), // Light Blue
                Color(0xFFE1F5FE), // Very Light Blue / White
                Color(0xFFFFF9C4), // Light Yellow
                Color(0xFFE8F5E9), // Very Light Green
                Color(0xFF81C784), // Light Green
              ],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Animated floating bubbles
              ..._buildFloatingBubbles(),
              // Content
              child!,
            ],
          ),
        );
      },
      child: widget.child,
    );
  }

  List<Widget> _buildFloatingBubbles() {
    return List.generate(8, (index) {
      final random = math.Random(index);
      final size = 40.0 + random.nextDouble() * 80;
      final startX = random.nextDouble();
      final startY = random.nextDouble();
      final speed = 0.5 + random.nextDouble() * 0.5;

      return Positioned(
        left: (startX + math.sin((_controller.value * speed + index) * 2 * math.pi) * 0.1) *
            MediaQuery.of(context).size.width,
        top: (startY + math.cos((_controller.value * speed + index) * 2 * math.pi) * 0.1) *
            MediaQuery.of(context).size.height,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                _getBubbleColor(index).withValues(alpha: 0.3),
                _getBubbleColor(index).withValues(alpha: 0.1),
                Colors.transparent,
              ],
            ),
          ),
        ),
      );
    });
  }

  Color _getBubbleColor(int index) {
    final colors = [
      const Color(0xFF4FC3F7), // Light Blue
      const Color(0xFFFFEB3B), // Yellow
      const Color(0xFF81C784), // Light Green
      const Color(0xFFE1F5FE), // White-ish Blue
      const Color(0xFFA5D6A7), // Mint Green
      const Color(0xFFFFF176), // Light Yellow
      const Color(0xFF4DD0E1), // Cyan
      const Color(0xFFC5E1A5), // Light Green
    ];
    return colors[index % colors.length];
  }
}

/// Hero page transition for smooth navigation between auth pages
class AuthPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final String? heroTag;

  AuthPageRoute({
    required this.page,
    this.heroTag,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Fade + Scale transition
            final fadeAnimation = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ));

            final scaleAnimation = Tween<double>(
              begin: 0.9,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ));

            final slideAnimation = Tween<Offset>(
              begin: const Offset(0.0, 0.1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ));

            return FadeTransition(
              opacity: fadeAnimation,
              child: ScaleTransition(
                scale: scaleAnimation,
                child: SlideTransition(
                  position: slideAnimation,
                  child: child,
                ),
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
