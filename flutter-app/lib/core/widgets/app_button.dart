import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

enum AppButtonVariant { filled, outlined, ghost, destructive }

enum AppButtonSize { small, medium, large }

class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final Widget? leading;
  final Widget? trailing;
  final bool loading;
  final bool fullWidth;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.size = AppButtonSize.medium,
    this.leading,
    this.trailing,
    this.loading = false,
    this.fullWidth = false,
  });

  const AppButton.outlined({
    super.key,
    required this.label,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.leading,
    this.trailing,
    this.loading = false,
    this.fullWidth = false,
  }) : variant = AppButtonVariant.outlined;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.leading,
    this.trailing,
    this.loading = false,
    this.fullWidth = false,
  }) : variant = AppButtonVariant.ghost;

  const AppButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.size = AppButtonSize.medium,
    this.leading,
    this.trailing,
    this.loading = false,
    this.fullWidth = false,
  }) : variant = AppButtonVariant.destructive;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onPressed == null || widget.loading) return;
    _scaleController.forward();
  }

  void _onTapUp(TapUpDetails _) => _scaleController.reverse();

  void _onTapCancel() => _scaleController.reverse();

  void _handleTap() {
    if (widget.loading) return;
    HapticFeedback.lightImpact();
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = widget.onPressed == null || widget.loading;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) =>
            Transform.scale(scale: _scaleAnimation.value, child: child),
        child: _ButtonContent(
          label: widget.label,
          variant: widget.variant,
          size: widget.size,
          leading: widget.leading,
          trailing: widget.trailing,
          loading: widget.loading,
          fullWidth: widget.fullWidth,
          disabled: disabled,
          isDark: isDark,
        ),
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  final String label;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final Widget? leading;
  final Widget? trailing;
  final bool loading;
  final bool fullWidth;
  final bool disabled;
  final bool isDark;

  const _ButtonContent({
    required this.label,
    required this.variant,
    required this.size,
    required this.leading,
    required this.trailing,
    required this.loading,
    required this.fullWidth,
    required this.disabled,
    required this.isDark,
  });

  EdgeInsetsGeometry get _padding => switch (size) {
    AppButtonSize.small => const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 8,
    ),
    AppButtonSize.medium => const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 13,
    ),
    AppButtonSize.large => const EdgeInsets.symmetric(
      horizontal: 28,
      vertical: 16,
    ),
  };

  double get _fontSize => switch (size) {
    AppButtonSize.small => 13,
    AppButtonSize.medium => 15,
    AppButtonSize.large => 16,
  };

  double get _iconSize => switch (size) {
    AppButtonSize.small => 15,
    AppButtonSize.medium => 17,
    AppButtonSize.large => 20,
  };

  double get _borderRadius => switch (size) {
    AppButtonSize.small => 10,
    AppButtonSize.medium => 14,
    AppButtonSize.large => 16,
  };

  Color _bgColor(bool isDark) {
    if (disabled) {
      return isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.05);
    }
    return switch (variant) {
      AppButtonVariant.filled =>
        isDark ? AppColors.primaryDark : AppColors.primary,
      AppButtonVariant.destructive =>
        isDark ? AppColors.errorBright : AppColors.error,
      AppButtonVariant.outlined || AppButtonVariant.ghost => Colors.transparent,
    };
  }

  Color _fgColor(bool isDark) {
    if (disabled) {
      return isDark
          ? Colors.white.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.3);
    }
    return switch (variant) {
      AppButtonVariant.filled || AppButtonVariant.destructive => Colors.white,
      AppButtonVariant.outlined =>
        isDark ? AppColors.primaryDark : AppColors.primary,
      AppButtonVariant.ghost =>
        isDark ? AppColors.textOnDarkPrimary : AppColors.textDark,
    };
  }

  Border? _border(bool isDark) {
    if (variant == AppButtonVariant.ghost) return null;
    final color = disabled
        ? (isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.12))
        : switch (variant) {
            AppButtonVariant.destructive => AppColors.errorDark,
            AppButtonVariant.filled || AppButtonVariant.outlined =>
              isDark ? AppColors.primaryDarkModeSoft : AppColors.primaryDark,
            AppButtonVariant.ghost => Colors.transparent,
          };
    return Border.all(color: color, width: 2);
  }

  @override
  Widget build(BuildContext context) {
    final fg = _fgColor(isDark);

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          SizedBox(
            width: _iconSize,
            height: _iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
        else if (leading != null)
          IconTheme(
            data: IconThemeData(color: fg, size: _iconSize),
            child: leading!,
          ),
        if ((loading || leading != null)) const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: _fontSize,
            fontWeight: FontWeight.w600,
            color: fg,
            height: 1.2,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          IconTheme(
            data: IconThemeData(color: fg, size: _iconSize),
            child: trailing!,
          ),
        ],
      ],
    );

    if (fullWidth) {
      content = Center(child: content);
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: disabled ? 0.6 : 1.0,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: _padding,
        decoration: BoxDecoration(
          color: _bgColor(isDark),
          borderRadius: BorderRadius.circular(_borderRadius),
          border: _border(isDark),
        ),
        child: content,
      ),
    );
  }
}
