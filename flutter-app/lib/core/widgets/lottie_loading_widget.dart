import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

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

  const LottieLoadingWidget.tiny({super.key})
    : size = 20,
      message = null,
      showMessage = false;

  const LottieLoadingWidget.small({super.key})
    : size = 32,
      message = null,
      showMessage = false;

  const LottieLoadingWidget.medium({super.key})
    : size = 64,
      message = null,
      showMessage = false;

  const LottieLoadingWidget.large({super.key, this.message})
    : size = 120,
      showMessage = true;

  @override
  Widget build(BuildContext context) {
    final animation = LayoutBuilder(
      builder: (context, constraints) {
        final boundedWidth = constraints.hasBoundedWidth && constraints.maxWidth > 0;
        final boundedHeight = constraints.hasBoundedHeight && constraints.maxHeight > 0;

        double effectiveSize = size;

        if (boundedWidth && boundedHeight) {
          effectiveSize = size.clamp(0.0, constraints.biggest.shortestSide);
        } else if (boundedWidth) {
          effectiveSize = size.clamp(0.0, constraints.maxWidth);
        } else if (boundedHeight) {
          effectiveSize = size.clamp(0.0, constraints.maxHeight);
        }

        if (effectiveSize <= 0) {
          effectiveSize = size;
        }

        return SizedBox(
          width: effectiveSize,
          height: effectiveSize,
          child: Lottie.asset(
            'animation/Sandy Loading.json',
            fit: BoxFit.contain,
            repeat: true,
          ),
        );
      },
    );

    // Keep compact variants layout-safe inside tight parent constraints
    // (e.g. small avatar placeholders) by avoiding a wrapping Column.
    if (!showMessage || message == null) {
      return animation;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        animation,
        const SizedBox(height: 16),
        Text(
          message!,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Full screen loading overlay
  static Widget fullScreen({String? message}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.3),
      child: Center(
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
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

  const LoadingScreen({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(child: LottieLoadingWidget.large(message: message));
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
