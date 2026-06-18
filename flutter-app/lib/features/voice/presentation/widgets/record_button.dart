import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';

/// Record Button Widget
/// Animated button for recording audio
class RecordButton extends StatefulWidget {
  final bool isRecording;
  final bool isProcessing;
  final VoidCallback onPressed;
  final Duration recordingDuration;

  const RecordButton({
    super.key,
    required this.isRecording,
    required this.isProcessing,
    required this.onPressed,
    this.recordingDuration = Duration.zero,
  });

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _animationController.repeat(reverse: true);
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _animationController.stop();
      _animationController.reset();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isRecording)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _formatDuration(widget.recordingDuration),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.errorBright,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        GestureDetector(
          onTap: widget.isProcessing ? null : widget.onPressed,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: widget.isRecording ? _scaleAnimation.value : 1.0,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isProcessing
                        ? Colors.grey
                        : (widget.isRecording
                              ? AppColors.errorBright
                              : AppColors.primary),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (widget.isRecording
                                    ? AppColors.errorBright
                                    : AppColors.primary)
                                .withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: widget.isProcessing
                      ? Center(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: LottieLoadingWidget.tiny(),
                          ),
                        )
                      : Icon(
                          widget.isRecording ? Icons.stop : Icons.mic,
                          color: Theme.of(context).colorScheme.surface,
                          size: 36,
                        ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.isProcessing
              ? 'voice.processing'.tr()
              : (widget.isRecording
                    ? 'voice.tapToStop'.tr()
                    : 'voice.tapToRecord'.tr()),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textGrey),
        ),
      ],
    );
  }
}
