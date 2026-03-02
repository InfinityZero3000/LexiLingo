---
name: celebrate-level-up-dialog
description: Show a full-screen overlay dialog when user levels up. Animate the level badge with scale+bounce, XP counter, and auto-dismiss after 3.5s. Should be triggerable from LevelProvider.
impact: MEDIUM
---

# Level-Up Celebration Dialog

## Context

When the user's XP crosses a level threshold, display a joyful full-screen celebration. It should feel rewarding but not block progress — auto-dismiss after 3.5s or on tap.

## Rule

Trigger via `LevelProvider.checkForLevelUp()` after any XP gain. Use `showGeneralDialog` with a transparent barrier and `ScaleTransition` + `FadeTransition` for the badge. Auto-dismiss with a `Future.delayed`.

## Correct Implementation

```dart
// features/level/presentation/widgets/level_up_dialog.dart
import 'package:flutter/material.dart';
import '../../domain/entities/level_entity.dart';

class LevelUpDialog extends StatefulWidget {
  final LevelTier newLevel;
  final int totalXP;

  const LevelUpDialog({
    super.key,
    required this.newLevel,
    required this.totalXP,
  });

  static Future<void> show(
    BuildContext context, {
    required LevelTier newLevel,
    required int totalXP,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Level Up',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      pageBuilder: (ctx, _, __) => LevelUpDialog(
        newLevel: newLevel,
        totalXP: totalXP,
      ),
    );
  }

  @override
  State<LevelUpDialog> createState() => _LevelUpDialogState();
}

class _LevelUpDialogState extends State<LevelUpDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _bounce = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
    ));

    _controller.forward();

    // Auto-dismiss after 3.5s
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.newLevel.colorValue);

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              width: 300,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // "LEVEL UP!" heading
                  Text('LEVEL UP!',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: color, letterSpacing: 2,
                    )),
                  const SizedBox(height: 16),
                  // Animated badge emoji
                  AnimatedBuilder(
                    animation: _bounce,
                    builder: (_, __) => Transform.scale(
                      scale: _bounce.value,
                      child: Text(
                        widget.newLevel.badge,
                        style: const TextStyle(fontSize: 72),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Level name
                  Text(
                    widget.newLevel.name,
                    style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.newLevel.code,
                    style: TextStyle(
                      fontSize: 16, color: color, fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Total XP
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${widget.totalXP} XP total',
                      style: TextStyle(color: color, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Keep going!',
                      style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

```dart
// Triggering from LevelProvider
// In LevelProvider, after loading new level data:
void _checkAndTriggerLevelUp(BuildContext context, LevelEntity newLevel) {
  if (_previousLevel != null &&
      _previousLevel!.current.code != newLevel.current.code) {
    // Level up detected!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LevelUpDialog.show(context,
        newLevel: newLevel.current,
        totalXP: newLevel.totalXP,
      );
    });
  }
  _previousLevel = newLevel;
}
```

## Incorrect Implementation

```dart
// Anti-pattern: blocking AlertDialog (modal, requires user interaction to dismiss)
showDialog(
  context: context,
  builder: (_) => AlertDialog(title: Text('Level Up!')),  // ❌ blocking
);

// Anti-pattern: auto-dismissed with Timer instead of Future.delayed
Timer(Duration(seconds: 3), () => Navigator.pop(context)); // ❌ use Future.delayed
```
