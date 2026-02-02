import 'dart:ui';
import 'package:flutter/material.dart';

/// Enhanced Lesson Card with glassmorphism and micro-animations
class GlassmorphicLessonCard extends StatefulWidget {
  final String title;
  final String? description;
  final bool isLocked;
  final bool isCompleted;
  final bool isCurrent;
  final int starsEarned;
  final double? bestScore;
  final int attemptsCount;
  final VoidCallback? onTap;
  final Color statusColor;

  const GlassmorphicLessonCard({
    super.key,
    required this.title,
    this.description,
    this.isLocked = false,
    this.isCompleted = false,
    this.isCurrent = false,
    this.starsEarned = 0,
    this.bestScore,
    this.attemptsCount = 0,
    this.onTap,
    this.statusColor = Colors.blue,
  });

  @override
  State<GlassmorphicLessonCard> createState() => _GlassmorphicLessonCardState();
}

class _GlassmorphicLessonCardState extends State<GlassmorphicLessonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (!widget.isLocked) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: widget.isLocked
                    ? null
                    : [
                        BoxShadow(
                          color: widget.isCurrent
                              ? widget.statusColor.withValues(alpha: 0.3 + (_glowAnimation.value * 0.2))
                              : Colors.black.withValues(alpha: 0.08),
                          blurRadius: widget.isCurrent ? 16 : 10,
                          offset: const Offset(0, 4),
                          spreadRadius: widget.isCurrent ? 2 : 0,
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: widget.isLocked ? 0 : 8,
                    sigmaY: widget.isLocked ? 0 : 8,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: widget.isLocked
                            ? [
                                Colors.grey[200]!,
                                Colors.grey[100]!,
                              ]
                            : isDark
                                ? [
                                    Colors.white.withValues(alpha: 0.12),
                                    Colors.white.withValues(alpha: 0.06),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: 0.95),
                                    Colors.white.withValues(alpha: 0.85),
                                  ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: widget.isCurrent
                            ? widget.statusColor.withValues(alpha: 0.5)
                            : widget.isLocked
                                ? Colors.grey[300]!
                                : (isDark 
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.grey[200]!),
                        width: widget.isCurrent ? 2 : 1,
                      ),
                    ),
                    child: Opacity(
                      opacity: widget.isLocked ? 0.6 : 1.0,
                      child: _buildCardContent(context),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row with stars
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: widget.isLocked ? Colors.grey : null,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (widget.isCompleted) _buildAnimatedStars(),
          ],
        ),

        if (widget.description != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.description!,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        const SizedBox(height: 14),

        // Stats row
        Row(
          children: [
            // Status badge
            _buildStatusBadge(),
            const Spacer(),
            // Score & Attempts
            if (widget.bestScore != null) _buildScoreBadge(),
            if (widget.attemptsCount > 0) ...[
              const SizedBox(width: 10),
              _buildAttemptsBadge(),
            ],
          ],
        ),

        // Continue button for current lesson
        if (widget.isCurrent) ...[
          const SizedBox(height: 14),
          _buildContinueButton(),
        ],
      ],
    );
  }

  Widget _buildAnimatedStars() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final isFilled = index < widget.starsEarned;

        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 400 + (index * 100)),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.scale(
              scale: isFilled ? (0.5 + value * 0.5) : 1.0,
              child: Opacity(
                opacity: isFilled ? value : 0.3,
                child: Icon(
                  isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 22,
                  color: isFilled ? Colors.amber : Colors.grey[300],
                ),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildStatusBadge() {
    String text;
    IconData icon;
    Color color = widget.statusColor;

    if (widget.isLocked) {
      text = 'Locked';
      icon = Icons.lock_outline;
      color = Colors.grey;
    } else if (widget.isCompleted) {
      text = 'Completed';
      icon = Icons.check_circle_outline;
      color = Colors.green;
    } else if (widget.isCurrent) {
      text = 'In Progress';
      icon = Icons.play_circle_outline;
    } else {
      text = 'Available';
      icon = Icons.circle_outlined;
      color = Colors.grey[500]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events_rounded,
            size: 14,
            color: Colors.amber[700],
          ),
          const SizedBox(width: 4),
          Text(
            '${widget.bestScore!.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.amber[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttemptsBadge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.replay_rounded,
          size: 14,
          color: Colors.grey[500],
        ),
        const SizedBox(width: 3),
        Text(
          '${widget.attemptsCount}',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildContinueButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.statusColor,
            widget.statusColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: widget.statusColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 22,
          ),
          SizedBox(width: 8),
          Text(
            'Continue',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated timeline node for roadmap
class AnimatedTimelineNode extends StatefulWidget {
  final bool isLocked;
  final bool isCompleted;
  final bool isCurrent;
  final bool isLast;
  final Color color;

  const AnimatedTimelineNode({
    super.key,
    this.isLocked = false,
    this.isCompleted = false,
    this.isCurrent = false,
    this.isLast = false,
    required this.color,
  });

  @override
  State<AnimatedTimelineNode> createState() => _AnimatedTimelineNodeState();
}

class _AnimatedTimelineNodeState extends State<AnimatedTimelineNode>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isCurrent) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(AnimatedTimelineNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrent != oldWidget.isCurrent) {
      if (widget.isCurrent) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: Column(
        children: [
          // Top line
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.color.withValues(alpha: 0.1),
                  widget.color.withValues(alpha: 0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          // Circle node
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: widget.isCurrent ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: widget.isLocked ? Colors.grey[300] : widget.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color,
                      width: 3,
                    ),
                    boxShadow: widget.isCurrent
                        ? [
                            BoxShadow(
                              color: widget.color.withValues(alpha: 0.4),
                              blurRadius: 14,
                              spreadRadius: 2 * _pulseAnimation.value,
                            ),
                          ]
                        : widget.isCompleted
                            ? [
                                BoxShadow(
                                  color: widget.color.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                  ),
                  child: Center(child: _buildNodeIcon()),
                ),
              );
            },
          ),
          // Bottom line
          if (!widget.isLast)
            Expanded(
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.color.withValues(alpha: 0.3),
                      widget.color.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeIcon() {
    if (widget.isLocked) {
      return Icon(
        Icons.lock_rounded,
        size: 16,
        color: Colors.grey[500],
      );
    }
    if (widget.isCompleted) {
      return const Icon(
        Icons.check_rounded,
        size: 18,
        color: Colors.white,
      );
    }
    if (widget.isCurrent) {
      return Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Progress indicator for lesson completion
class LessonProgressIndicator extends StatelessWidget {
  final double progress;
  final Color color;
  final double size;
  final double strokeWidth;

  const LessonProgressIndicator({
    super.key,
    required this.progress,
    this.color = Colors.blue,
    this.size = 48,
    this.strokeWidth = 4,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: strokeWidth,
              color: color.withValues(alpha: 0.15),
            ),
          ),
          // Progress circle
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            tween: Tween(begin: 0.0, end: progress.clamp(0.0, 1.0)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: strokeWidth,
                  color: color,
                  strokeCap: StrokeCap.round,
                ),
              );
            },
          ),
          // Percentage text
          Text(
            '${(progress * 100).toInt()}%',
            style: TextStyle(
              fontSize: size * 0.25,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
