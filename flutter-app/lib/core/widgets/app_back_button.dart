import 'package:flutter/material.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    this.onPressed,
    this.icon = Icons.arrow_back_ios_new_rounded,
    this.color,
    this.iconSize = 20,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final Color? color;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed ?? () => Navigator.maybePop(context),
    icon: Icon(icon, color: color, size: iconSize),
    tooltip: tooltip ?? MaterialLocalizations.of(context).backButtonTooltip,
    style: IconButton.styleFrom(
      backgroundColor: Colors.transparent,
      minimumSize: const Size.square(48),
      side: BorderSide.none,
    ),
  );
}
