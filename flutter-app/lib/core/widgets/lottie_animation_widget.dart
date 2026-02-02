import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Available Lottie animations in the app
enum LottieAnimation {
  /// Welcome animation for login/onboarding
  welcome('animation/Welcome.json'),
  
  /// Sandy loading animation
  sandyLoading('animation/Sandy Loading.json'),
  
  /// Confetti celebration
  confetti('animation/Confetti.json'),
  
  /// Live Love Learn animation
  liveLoveLearn('animation/Live Love Learn.json'),
  
  /// Pulse loader animation (custom)
  pulseLoader('animation/PulseLoader.json'),
  
  /// Success checkmark animation (custom)
  successCheck('animation/SuccessCheck.json'),
  
  /// Spinning dots loader (custom)
  spinningDots('animation/SpinningDots.json'),
  
  /// Heartbeat animation (custom)
  heartbeat('animation/HeartBeat.json'),
  
  /// Star burst celebration (custom)
  starBurst('animation/StarBurst.json');

  final String path;
  const LottieAnimation(this.path);
}

/// Reusable Lottie Animation Widget
/// Easy to use wrapper for all Lottie animations in the app
class LottieAnimationWidget extends StatelessWidget {
  final LottieAnimation animation;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool repeat;
  final bool reverse;
  final AnimationController? controller;
  final void Function(LottieComposition)? onLoaded;
  final Duration? duration;

  const LottieAnimationWidget({
    super.key,
    required this.animation,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.repeat = true,
    this.reverse = false,
    this.controller,
    this.onLoaded,
    this.duration,
  });

  /// Quick constructor for success checkmark
  const LottieAnimationWidget.success({
    super.key,
    this.width = 80,
    this.height = 80,
    this.fit = BoxFit.contain,
    this.repeat = false,
    this.reverse = false,
    this.controller,
    this.onLoaded,
    this.duration,
  }) : animation = LottieAnimation.successCheck;

  /// Quick constructor for heartbeat
  const LottieAnimationWidget.heartbeat({
    super.key,
    this.width = 60,
    this.height = 60,
    this.fit = BoxFit.contain,
    this.repeat = true,
    this.reverse = false,
    this.controller,
    this.onLoaded,
    this.duration,
  }) : animation = LottieAnimation.heartbeat;

  /// Quick constructor for star burst celebration
  const LottieAnimationWidget.starBurst({
    super.key,
    this.width = 100,
    this.height = 100,
    this.fit = BoxFit.contain,
    this.repeat = false,
    this.reverse = false,
    this.controller,
    this.onLoaded,
    this.duration,
  }) : animation = LottieAnimation.starBurst;

  /// Quick constructor for loading
  const LottieAnimationWidget.loading({
    super.key,
    this.width = 80,
    this.height = 80,
    this.fit = BoxFit.contain,
    this.repeat = true,
    this.reverse = false,
    this.controller,
    this.onLoaded,
    this.duration,
  }) : animation = LottieAnimation.spinningDots;

  /// Quick constructor for pulse loader
  const LottieAnimationWidget.pulse({
    super.key,
    this.width = 60,
    this.height = 60,
    this.fit = BoxFit.contain,
    this.repeat = true,
    this.reverse = false,
    this.controller,
    this.onLoaded,
    this.duration,
  }) : animation = LottieAnimation.pulseLoader;

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      animation.path,
      width: width,
      height: height,
      fit: fit,
      repeat: repeat,
      reverse: reverse,
      controller: controller,
      onLoaded: onLoaded,
      frameRate: FrameRate.max,
      errorBuilder: (context, error, stackTrace) {
        // Fallback to simple loading indicator
        return SizedBox(
          width: width ?? 80,
          height: height ?? 80,
          child: const CircularProgressIndicator(),
        );
      },
    );
  }
}

/// Animated Success Dialog
/// Shows a success animation with optional message
class AnimatedSuccessDialog extends StatelessWidget {
  final String? title;
  final String? message;
  final VoidCallback? onDismiss;
  final Duration autoCloseDuration;

  const AnimatedSuccessDialog({
    super.key,
    this.title,
    this.message,
    this.onDismiss,
    this.autoCloseDuration = const Duration(seconds: 2),
  });

  /// Show the dialog
  static Future<void> show(
    BuildContext context, {
    String? title,
    String? message,
    Duration autoCloseDuration = const Duration(seconds: 2),
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AnimatedSuccessDialog(
        title: title,
        message: message,
        autoCloseDuration: autoCloseDuration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Auto close after duration
    Future.delayed(autoCloseDuration, () {
      if (context.mounted) {
        Navigator.of(context).pop();
        onDismiss?.call();
      }
    });

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LottieAnimationWidget.success(
              width: 100,
              height: 100,
            ),
            if (title != null) ...[
              const SizedBox(height: 16),
              Text(
                title!,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated Celebration Overlay
/// Full screen celebration with star burst
class StarBurstOverlay extends StatefulWidget {
  final Widget child;
  final bool showCelebration;
  final VoidCallback? onAnimationComplete;

  const StarBurstOverlay({
    super.key,
    required this.child,
    this.showCelebration = false,
    this.onAnimationComplete,
  });

  @override
  State<StarBurstOverlay> createState() => _StarBurstOverlayState();
}

class _StarBurstOverlayState extends State<StarBurstOverlay> {
  bool _showAnimation = false;

  @override
  void didUpdateWidget(StarBurstOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showCelebration && !oldWidget.showCelebration) {
      _triggerAnimation();
    }
  }

  void _triggerAnimation() {
    setState(() => _showAnimation = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _showAnimation = false);
        widget.onAnimationComplete?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showAnimation)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Lottie.asset(
                  LottieAnimation.starBurst.path,
                  width: 200,
                  height: 200,
                  repeat: false,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
