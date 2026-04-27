import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Animated gradient XP progress bar widget.
///
/// Shows current level, XP progress, and XP needed for next level.
class XPProgressBar extends StatefulWidget {
  final int totalXp;
  final int numericLevel;
  final double progressPercent;
  final int xpForNextLevel;
  final int currentXpInLevel;
  final bool compact;

  const XPProgressBar({
    super.key,
    required this.totalXp,
    required this.numericLevel,
    required this.progressPercent,
    required this.xpForNextLevel,
    required this.currentXpInLevel,
    this.compact = false,
  });

  @override
  State<XPProgressBar> createState() => _XPProgressBarState();
}

class _XPProgressBarState extends State<XPProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;
  double _previousProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _previousProgress = 0;
    _progressAnimation = Tween<double>(
      begin: 0,
      end: (widget.progressPercent / 100).clamp(0.0, 1.0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void didUpdateWidget(XPProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progressPercent != widget.progressPercent) {
      _previousProgress = (oldWidget.progressPercent / 100).clamp(0.0, 1.0);
      _progressAnimation = Tween<double>(
        begin: _previousProgress,
        end: (widget.progressPercent / 100).clamp(0.0, 1.0),
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompact();
    }
    return _buildFull();
  }

  Widget _buildCompact() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _levelBadge(size: 28, fontSize: 11),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _animatedBar(height: 6),
              const SizedBox(height: 2),
              Text(
                '${widget.currentXpInLevel}/${widget.xpForNextLevel} XP',
                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFull() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _levelBadge(size: 36, fontSize: 14),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'games.levelDisplay'.tr(namedArgs: {'level': '${widget.numericLevel}'}),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${widget.totalXp} total XP',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              '${widget.currentXpInLevel}/${widget.xpForNextLevel} XP',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _animatedBar(height: 10),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${widget.progressPercent.toStringAsFixed(0)}% to next level',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            Text(
              'games.levelNextShort'.tr(namedArgs: {'level': '${widget.numericLevel + 1}'}),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _levelBadge({required double size, required double fontSize}) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.primary, Color(0xFF5B9BF5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '${widget.numericLevel}',
        style: TextStyle(
          color: AppColors.surfaceLight,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }

  Widget _animatedBar({required double height}) {
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            final fillWidth = barWidth * _progressAnimation.value;
            return Stack(
              children: [
                Container(
                  height: height,
                  width: barWidth,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
                Container(
                  height: height,
                  width: fillWidth.clamp(0.0, barWidth),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, Color(0xFF38B2FF)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(height / 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
