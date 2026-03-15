import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';
import '../widgets/auth_gradient_background.dart';

/// Welcome page shown after successful login
/// Displays a welcome animation before navigating to the main screen
class WelcomePage extends StatefulWidget {
  final VoidCallback onComplete;
  final String? userName;

  const WelcomePage({super.key, required this.onComplete, this.userName});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showContinueButton = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);

    // Show continue button after animation completes or after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showContinueButton = true;
        });
      }
    });

    // Auto-navigate after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthGradientBackground(
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),

              // Frosted glass card: animation + texts
              _buildFrostedContentCard(context),

              const Spacer(flex: 1),

              // Continue button
              AnimatedOpacity(
                opacity: _showContinueButton ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: _buildContinueButton(context),
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  /// Frosted glass panel that backs the animation + all text content
  Widget _buildFrostedContentCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.40),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildWelcomeAnimation(),
                const SizedBox(height: 24),
                _buildWelcomeText(context),
                const SizedBox(height: 12),
                if (widget.userName != null) _buildUserGreeting(context),
                const SizedBox(height: 16),
                _buildMotivationalMessage(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeAnimation() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 350, maxHeight: 200),
      child: Lottie.asset(
        'animation/Welcome.json',
        controller: _controller,
        fit: BoxFit.contain,
        onLoaded: (composition) {
          _controller
            ..duration = composition.duration
            ..forward();
        },
        repeat: true,
        animate: true,
        errorBuilder: (context, error, stackTrace) {
          // Fallback widget if Lottie fails
          return _buildFallbackAnimation();
        },
      ),
    );
  }

  /// Fallback animation when Lottie fails to load
  Widget _buildFallbackAnimation() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.2),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.waving_hand_rounded,
          size: 80,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildWelcomeText(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        // Clamp opacity to valid range (easeOutBack can overshoot)
        final opacity = value.clamp(0.0, 1.0);
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: Text(
        'Welcome to LexiLingo!',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
          shadows: [
            Shadow(
              color: Colors.white.withValues(alpha: 0.85),
              offset: const Offset(0, 0),
              blurRadius: 14,
            ),
            Shadow(
              color: Colors.black.withValues(alpha: 0.25),
              offset: const Offset(1, 2),
              blurRadius: 6,
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildUserGreeting(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        final opacity = value.clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Hello, ',
            style: theme.textTheme.titleLarge?.copyWith(
              color: isDark ? Colors.white70 : Colors.grey[700],
              shadows: [
                Shadow(
                  color: Colors.white.withValues(alpha: 0.7),
                  blurRadius: 10,
                ),
                Shadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  offset: const Offset(1, 1),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          Text(
            widget.userName!,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.accentYellow,
              shadows: [
                Shadow(
                  color: Colors.white.withValues(alpha: 0.7),
                  blurRadius: 10,
                ),
                Shadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  offset: const Offset(1, 1),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
          Text(' ', style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }

  Widget _buildMotivationalMessage(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final messages = [
      "Ready to learn something new today?",
      "Your language journey continues!",
      "Let's make today count!",
      "Time to expand your vocabulary!",
      "Learning is the greatest adventure!",
    ];

    // Pick a random message
    final message = messages[DateTime.now().second % messages.length];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        final opacity = value.clamp(0.0, 1.0);
        return Opacity(opacity: opacity, child: child);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          message,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isDark ? Colors.white70 : Colors.grey[700],
            fontStyle: FontStyle.italic,
            shadows: [
              Shadow(
                color: Colors.white.withValues(alpha: 0.65),
                blurRadius: 8,
              ),
              Shadow(
                color: Colors.black.withValues(alpha: 0.15),
                offset: const Offset(0, 1),
                blurRadius: 4,
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildContinueButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4FC3F7), Color(0xFF81C784)],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4FC3F7).withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: widget.onComplete,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Let\'s Start',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
