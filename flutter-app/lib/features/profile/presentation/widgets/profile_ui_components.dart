import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Animated gradient background for profile header
class AnimatedProfileBackground extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  final Duration duration;

  const AnimatedProfileBackground({
    super.key,
    required this.child,
    this.colors = const [
      AppColors.primary,
      AppColors.primaryDark,
      AppColors.purple,
    ],
    this.duration = const Duration(seconds: 4),
  });

  @override
  State<AnimatedProfileBackground> createState() =>
      _AnimatedProfileBackgroundState();
}

class _AnimatedProfileBackgroundState extends State<AnimatedProfileBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this)
      ..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.colors,
              stops: [0.0, 0.5 + (_animation.value * 0.2), 1.0],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Glassmorphic stat card with animated value changes
class GlassmorphicStatCard extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String? subtitle;
  final bool isAction;
  final VoidCallback? onTap;
  final double valueFontSize;
  final EdgeInsetsGeometry contentPadding;
  final double iconBoxSize;
  final double iconSize;
  final double titleFontSize;
  final double subtitleFontSize;
  final double middleSpacing;

  const GlassmorphicStatCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    this.subtitle,
    this.isAction = false,
    this.onTap,
    this.valueFontSize = 42,
    this.contentPadding = const EdgeInsets.all(16),
    this.iconBoxSize = 48,
    this.iconSize = 22,
    this.titleFontSize = 14,
    this.subtitleFontSize = 12,
    this.middleSpacing = 18,
  });

  @override
  State<GlassmorphicStatCard> createState() => _GlassmorphicStatCardState();
}

class _GlassmorphicStatCardState extends State<GlassmorphicStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
      ? widget.color.withValues(alpha: 0.12)
      : widget.color.withValues(alpha: 0.08);
    final borderColor = isDark
      ? widget.color.withValues(alpha: 0.36)
      : widget.color.withValues(alpha: 0.28);
    final iconBgColor = isDark
      ? widget.color.withValues(alpha: 0.22)
      : widget.color.withValues(alpha: 0.16);
    final titleColor = isDark
        ? AppColors.textInverted.withValues(alpha: 0.7)
        : AppColors.textGrey;
    final valueColor = isDark ? AppColors.textInverted : AppColors.textDark;
    final subtitleColor = isDark
        ? AppColors.textInverted.withValues(alpha: 0.6)
        : AppColors.textSlate;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.onTap != null ? _onTapDown : null,
      onTapUp: widget.onTap != null ? _onTapUp : null,
      onTapCancel: widget.onTap != null ? _onTapCancel : null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: surfaceColor,
                border: Border.all(
                  color: borderColor,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: isDark ? 0.08 : 0.14),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: widget.contentPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: widget.iconBoxSize,
                          height: widget.iconBoxSize,
                          decoration: BoxDecoration(
                            color: iconBgColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.color,
                            size: widget.iconSize,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: widget.titleFontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: widget.middleSpacing),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        fontSize: widget.valueFontSize,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: valueColor,
                        letterSpacing: -1,
                      ),
                      child: Text(widget.value),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.subtitle!,
                              style: TextStyle(
                                color: widget.isAction ? widget.color : subtitleColor,
                                fontSize: widget.subtitleFontSize,
                                fontWeight: widget.isAction
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (widget.isAction)
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: widget.color,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Animated progress bar with gradient
class AnimatedProgressBar extends StatefulWidget {
  final double progress;
  final Color primaryColor;
  final Color? secondaryColor;
  final double height;
  final Duration duration;

  const AnimatedProgressBar({
    super.key,
    required this.progress,
    required this.primaryColor,
    this.secondaryColor,
    this.height = 10,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<AnimatedProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: widget.progress.clamp(0.0, 1.0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));

    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _progressAnimation =
          Tween<double>(
            begin: _progressAnimation.value,
            end: widget.progress.clamp(0.0, 1.0),
          ).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor =
        widget.secondaryColor ?? widget.primaryColor.withValues(alpha: 0.6);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.height / 2),
          child: Stack(
            children: [
              // Background
              Container(
                height: widget.height,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDarkMuted : AppColors.slate200,
                ),
              ),
              // Progress
              FractionallySizedBox(
                widthFactor: _progressAnimation.value,
                child: Container(
                  height: widget.height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.primaryColor, secondaryColor],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  child: _progressAnimation.value > 0.1
                      ? ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment(_shimmerAnimation.value - 1, 0),
                              end: Alignment(_shimmerAnimation.value, 0),
                              colors: [
                                Colors.transparent,
                                Colors.white.withValues(alpha: 0.3),
                                Colors.transparent,
                              ],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.srcATop,
                          child: Container(color: Theme.of(context).colorScheme.surface),
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Social stat with micro-animation
class AnimatedSocialStat extends StatefulWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const AnimatedSocialStat({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  State<AnimatedSocialStat> createState() => _AnimatedSocialStatState();
}

class _AnimatedSocialStatState extends State<AnimatedSocialStat>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _iconBounceAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _iconBounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -4.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -4.0, end: 0.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -2.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -2.0, end: 0.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Auto-play animation on build
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _controller.forward(from: 0);
        widget.onTap?.call();
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.translate(
                      offset: Offset(0, _iconBounceAnimation.value),
                      child: Icon(widget.icon, size: 18, color: widget.color),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: widget.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Edit profile button with glassmorphism
class GlassmorphicEditButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String text;
  final IconData icon;

  const GlassmorphicEditButton({
    super.key,
    this.onPressed,
    this.text = 'Edit Profile',
    this.icon = Icons.edit,
  });

  @override
  State<GlassmorphicEditButton> createState() => _GlassmorphicEditButtonState();
}

class _GlassmorphicEditButtonState extends State<GlassmorphicEditButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onPressed?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.surfaceLight.withValues(alpha: 0.2),
                        AppColors.surfaceLight.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 16, color: Theme.of(context).colorScheme.surface),
                      const SizedBox(width: 6),
                      Text(
                        widget.text,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.surface,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Animated weekly activity bar
class AnimatedActivityBar extends StatefulWidget {
  final String label;
  final double value; // 0.0 to 1.0
  final int xpValue;
  final Color color;
  final Duration delay;

  const AnimatedActivityBar({
    super.key,
    required this.label,
    required this.value,
    required this.xpValue,
    this.color = AppColors.primary,
    this.delay = Duration.zero,
  });

  @override
  State<AnimatedActivityBar> createState() => _AnimatedActivityBarState();
}

class _AnimatedActivityBarState extends State<AnimatedActivityBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _heightAnimation = Tween<double>(
      begin: 0.0,
      end: widget.value.clamp(0.0, 1.0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.xpValue > 0)
                AnimatedOpacity(
                  opacity: _heightAnimation.value > 0.5 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    '${widget.xpValue}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: widget.color,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Container(
                width: 32,
                height: 80 * _heightAnimation.value + 4, // Min height of 4
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [widget.color, widget.color.withValues(alpha: 0.6)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.grey500 : AppColors.grey600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Glassmorphic container wrapper
class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color? borderColor;
  final double blur;

  const GlassmorphicContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.borderRadius = 16,
    this.borderColor,
    this.blur = 10,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        AppColors.surfaceLight.withValues(alpha: 0.1),
                        AppColors.surfaceLight.withValues(alpha: 0.05),
                      ]
                    : [
                        AppColors.surfaceLight.withValues(alpha: 0.8),
                        AppColors.surfaceLight.withValues(alpha: 0.6),
                      ],
              ),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color:
                    borderColor ??
                    (isDark
                        ? AppColors.surfaceLight.withValues(alpha: 0.1)
                        : AppColors.surfaceLight.withValues(alpha: 0.5)),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textDark.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
