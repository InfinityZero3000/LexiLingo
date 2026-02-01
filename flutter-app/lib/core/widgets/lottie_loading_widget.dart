import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// A beautiful loading widget using Lottie animation
/// Can be used as a replacement for CircularProgressIndicator
class LottieLoadingWidget extends StatelessWidget {
  final double size;
  final String? message;
  final bool showMessage;

  const LottieLoadingWidget({
    super.key,
    this.size = 120,
    this.message,
    this.showMessage = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Lottie.asset(
            'animation/Sandy Loading.json',
            fit: BoxFit.contain,
            repeat: true,
          ),
        ),
        if (showMessage && message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Small loading indicator (for buttons, inline)
  factory LottieLoadingWidget.small() {
    return const LottieLoadingWidget(size: 40);
  }

  /// Medium loading indicator (for cards, sections)
  factory LottieLoadingWidget.medium() {
    return const LottieLoadingWidget(size: 80);
  }

  /// Large loading indicator (for full page loading)
  factory LottieLoadingWidget.large({String? message}) {
    return LottieLoadingWidget(
      size: 150,
      message: message,
      showMessage: message != null,
    );
  }

  /// Full screen loading overlay
  static Widget fullScreen({String? message}) {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: LottieLoadingWidget.large(message: message),
        ),
      ),
    );
  }
}

/// A centered loading widget for use in Scaffold body
class LoadingScreen extends StatelessWidget {
  final String? message;

  const LoadingScreen({
    super.key,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LottieLoadingWidget.large(message: message),
    );
  }
}

/// Loading overlay that can be shown on top of content
class LoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool isLoading;
  final String? message;

  const LoadingOverlay({
    super.key,
    required this.child,
    required this.isLoading,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: LottieLoadingWidget.fullScreen(message: message),
          ),
      ],
    );
  }
}
