import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class AppSurface extends StatefulWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.variant = TactileSurfaceVariant.clean,
    this.fill,
    this.accent,
    this.radius,
    this.padding,
    this.onTap,
    this.diagnosticId,
  });

  final Widget child;
  final TactileSurfaceVariant variant;
  final Color? fill;
  final Color? accent;
  final BorderRadius? radius;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final String? diagnosticId;

  @override
  State<AppSurface> createState() => _AppSurfaceState();
}

class _AppSurfaceState extends State<AppSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tactile =
        theme.extension<AppTactileTheme>() ?? AppTactileTheme.from(theme);
    final radius = widget.radius ?? AppRadius.xlAll;
    final interactive = widget.onTap != null;
    final decoration = tactile.decoration(
      variant: interactive && widget.variant == TactileSurfaceVariant.elevated
          ? TactileSurfaceVariant.interactive
          : widget.variant,
      fill: widget.fill ?? theme.colorScheme.surface,
      accent: widget.accent,
      borderRadius: radius,
      states: {if (_pressed) WidgetState.pressed},
      diagnosticId: widget.diagnosticId,
    );

    final content = Padding(
      padding: widget.padding ?? EdgeInsets.zero,
      child: widget.child,
    );

    return DecoratedBox(
      decoration: decoration,
      child: ClipRRect(
        borderRadius: radius,
        child: interactive
            ? Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.onTap,
                  onHighlightChanged: (value) =>
                      setState(() => _pressed = value),
                  child: content,
                ),
              )
            : content,
      ),
    );
  }
}
