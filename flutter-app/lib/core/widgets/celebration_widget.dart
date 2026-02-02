import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Celebration overlay widget with Lottie confetti animation
/// Used when user completes a lesson, course, or achievement
class CelebrationOverlay extends StatefulWidget {
  final Widget child;
  final bool show;
  final VoidCallback? onComplete;
  final Duration duration;

  const CelebrationOverlay({
    super.key,
    required this.child,
    this.show = false,
    this.onComplete,
    this.duration = const Duration(seconds: 4),
  });

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showConfetti = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    
    if (widget.show) {
      _startCelebration();
    }
  }

  @override
  void didUpdateWidget(CelebrationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show) {
      _startCelebration();
    }
  }

  void _startCelebration() {
    setState(() {
      _showConfetti = true;
    });

    Future.delayed(widget.duration, () {
      if (mounted) {
        setState(() {
          _showConfetti = false;
        });
        widget.onComplete?.call();
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
    return Stack(
      children: [
        widget.child,
        if (_showConfetti) ...[
          // Center confetti burst
          Positioned.fill(
            child: IgnorePointer(
              child: Lottie.asset(
                'animation/Confetti.json',
                controller: _controller,
                onLoaded: (composition) {
                  _controller
                    ..duration = composition.duration
                    ..forward();
                },
                fit: BoxFit.cover,
                repeat: false,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Standalone celebration screen for major achievements
class CelebrationScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? xpEarned;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onContinue;
  final List<Widget>? extraContent;

  const CelebrationScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.xpEarned,
    this.icon = Icons.emoji_events,
    this.iconColor = Colors.amber,
    required this.onContinue,
    this.extraContent,
  });

  @override
  State<CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen>
    with TickerProviderStateMixin {
  late AnimationController _confettiController;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _confettiController = AnimationController(vsync: this);
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeIn),
    );

    // Start animations
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _scaleController.forward();
      }
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.primaryColor.withValues(alpha: 0.1),
                  theme.scaffoldBackgroundColor,
                ],
              ),
            ),
          ),

          // Confetti animation
          Positioned.fill(
            child: IgnorePointer(
              child: Lottie.asset(
                'animation/Confetti.json',
                controller: _confettiController,
                onLoaded: (composition) {
                  _confettiController
                    ..duration = composition.duration
                    ..forward();
                },
                fit: BoxFit.cover,
                repeat: false,
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // Animated icon
                  AnimatedBuilder(
                    animation: _scaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: widget.iconColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.iconColor.withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        size: 80,
                        color: widget.iconColor,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title with fade animation
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      widget.title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 12),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        widget.subtitle!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // XP earned badge
                  if (widget.xpEarned != null)
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildXpBadge(context),
                    ),

                  // Extra content
                  if (widget.extraContent != null) ...[
                    const SizedBox(height: 24),
                    ...widget.extraContent!.map((w) => FadeTransition(
                          opacity: _fadeAnimation,
                          child: w,
                        )),
                  ],

                  const Spacer(flex: 2),

                  // Continue button
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: widget.onContinue,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildXpBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.shade400,
            Colors.orange.shade400,
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.4),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.stars, color: Colors.white, size: 28),
          const SizedBox(width: 8),
          Text(
            '+${widget.xpEarned} XP',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Show celebration dialog/overlay
void showCelebration(BuildContext context, {
  required String title,
  String? subtitle,
  String? xpEarned,
  IconData icon = Icons.emoji_events,
  Color iconColor = Colors.amber,
  VoidCallback? onDismiss,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return CelebrationScreen(
        title: title,
        subtitle: subtitle,
        xpEarned: xpEarned,
        icon: icon,
        iconColor: iconColor,
        onContinue: () {
          Navigator.of(context).pop();
          onDismiss?.call();
        },
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    },
  );
}
