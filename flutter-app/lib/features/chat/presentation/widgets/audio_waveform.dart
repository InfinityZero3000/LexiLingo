import 'dart:math';
import 'package:flutter/material.dart';

/// Audio Waveform Widget for voice recording visualization
/// Creates an animated waveform effect during voice recording
class AudioWaveform extends StatefulWidget {
  final bool isRecording;
  final Color color;
  final int barCount;
  final double barWidth;
  final double minHeight;
  final double maxHeight;
  final Duration animationDuration;

  const AudioWaveform({
    super.key,
    required this.isRecording,
    this.color = Colors.red,
    this.barCount = 20,
    this.barWidth = 3,
    this.minHeight = 4,
    this.maxHeight = 32,
    this.animationDuration = const Duration(milliseconds: 150),
  });

  @override
  State<AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveform>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _controllers = List.generate(widget.barCount, (index) {
      return AnimationController(
        vsync: this,
        duration: Duration(
          milliseconds:
              widget.animationDuration.inMilliseconds + _random.nextInt(100),
        ),
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(
        begin: widget.minHeight,
        end: widget.maxHeight,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOut,
      ));
    }).toList();

    if (widget.isRecording) {
      _startAnimations();
    }
  }

  void _startAnimations() {
    for (var i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 50), () {
        if (mounted && widget.isRecording) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  void _stopAnimations() {
    for (var controller in _controllers) {
      controller.stop();
      controller.animateTo(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void didUpdateWidget(AudioWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording != oldWidget.isRecording) {
      if (widget.isRecording) {
        _startAnimations();
      } else {
        _stopAnimations();
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.maxHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(widget.barCount, (index) {
          return AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              return Container(
                width: widget.barWidth,
                height: widget.isRecording 
                    ? _animations[index].value 
                    : widget.minHeight,
                margin: EdgeInsets.symmetric(horizontal: widget.barWidth / 2),
                decoration: BoxDecoration(
                  color: widget.color.withValues(
                    alpha: 0.5 + (_animations[index].value / widget.maxHeight) * 0.5,
                  ),
                  borderRadius: BorderRadius.circular(widget.barWidth / 2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

/// Compact voice recording indicator with waveform
class VoiceRecordingIndicator extends StatelessWidget {
  final bool isRecording;
  final bool isProcessing;
  final Duration recordingDuration;
  final VoidCallback onCancel;
  final Color recordingColor;
  final Color processingColor;

  const VoiceRecordingIndicator({
    super.key,
    required this.isRecording,
    required this.isProcessing,
    required this.recordingDuration,
    required this.onCancel,
    this.recordingColor = Colors.red,
    this.processingColor = Colors.blue,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isRecording
              ? [
                  recordingColor.withValues(alpha: 0.15),
                  recordingColor.withValues(alpha: 0.05),
                ]
              : [
                  processingColor.withValues(alpha: 0.15),
                  processingColor.withValues(alpha: 0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRecording
              ? recordingColor.withValues(alpha: 0.3)
              : processingColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          if (isRecording) ...[
            // Pulsing recording indicator
            _PulsingDot(color: recordingColor),
            const SizedBox(width: 12),
            // Waveform
            Expanded(
              child: AudioWaveform(
                isRecording: isRecording,
                color: recordingColor,
                barCount: 15,
                barWidth: 3,
                maxHeight: 24,
              ),
            ),
            const SizedBox(width: 12),
            // Duration
            Text(
              _formatDuration(recordingDuration),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: recordingColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            // Cancel button
            IconButton(
              onPressed: onCancel,
              icon: Icon(Icons.close, color: recordingColor),
              style: IconButton.styleFrom(
                backgroundColor: recordingColor.withValues(alpha: 0.1),
              ),
            ),
          ] else if (isProcessing) ...[
            // Processing spinner
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(processingColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Processing your voice...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pulsing dot animation for recording indicator
class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow
            Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
            // Inner dot
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Voice message playback widget with waveform visualization
class VoiceMessagePlayback extends StatefulWidget {
  final Duration duration;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final bool isPlaying;
  final double progress;
  final Color color;

  const VoiceMessagePlayback({
    super.key,
    required this.duration,
    required this.onPlay,
    required this.onPause,
    required this.isPlaying,
    this.progress = 0.0,
    this.color = Colors.blue,
  });

  @override
  State<VoiceMessagePlayback> createState() => _VoiceMessagePlaybackState();
}

class _VoiceMessagePlaybackState extends State<VoiceMessagePlayback> {
  // Pre-generate random heights for waveform bars
  late List<double> _barHeights;

  @override
  void initState() {
    super.initState();
    final random = Random(42); // Fixed seed for consistent appearance
    _barHeights = List.generate(30, (_) => 0.3 + random.nextDouble() * 0.7);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: widget.isPlaying ? widget.onPause : widget.onPlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Static waveform with progress overlay
          Expanded(
            child: SizedBox(
              height: 32,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = 3.0;
                  final barSpacing = 2.0;
                  final totalBarWidth = barWidth + barSpacing;
                  final barCount = (constraints.maxWidth / totalBarWidth).floor();
                  final progressBarCount = (barCount * widget.progress).floor();

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(barCount, (index) {
                      final height = _barHeights[index % _barHeights.length] * 32;
                      final isPlayed = index < progressBarCount;
                      return Container(
                        width: barWidth,
                        height: height,
                        decoration: BoxDecoration(
                          color: isPlayed
                              ? widget.color
                              : widget.color.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(barWidth / 2),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Duration
          Text(
            _formatDuration(widget.duration),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: widget.color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
