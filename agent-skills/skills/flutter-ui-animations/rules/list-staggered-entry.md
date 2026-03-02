---
name: list-staggered-entry
description: Animate list items with a staggered FadeSlide-in on first load. Each item delays by 50ms * index. Use AnimationController + CurvedAnimation, never Timer-based hacks.
impact: HIGH
---

# Staggered List Entry Animation

## Context

When the Home page or Notifications page loads fresh data, items should animate in sequentially to signal new content and create visual delight. Items slide up 20px and fade in with 50ms stagger per item.

## Rule

Use a `SingleTickerProviderStateMixin` on the screen or a dedicated `StaggeredListWidget`. Cap stagger at index 6 (300ms max total) to avoid long waits for users with many items.

## Correct Implementation

```dart
// core/widgets/staggered_list.dart
import 'package:flutter/material.dart';

class StaggeredList extends StatefulWidget {
  final List<Widget> children;
  final Duration itemDelay;
  final Duration itemDuration;
  final Offset slideOffset;

  const StaggeredList({
    super.key,
    required this.children,
    this.itemDelay = const Duration(milliseconds: 50),
    this.itemDuration = const Duration(milliseconds: 350),
    this.slideOffset = const Offset(0, 0.08), // 8% down → up
  });

  @override
  State<StaggeredList> createState() => _StaggeredListState();
}

class _StaggeredListState extends State<StaggeredList>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _fades;
  late List<Animation<Offset>> _slides;

  @override
  void initState() {
    super.initState();
    final count = widget.children.length;
    _controllers = List.generate(count, (i) => AnimationController(
      vsync: this,
      duration: widget.itemDuration,
    ));

    _fades = _controllers.map((c) => Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: c, curve: Curves.easeOut))).toList();

    _slides = _controllers.map((c) =>
        Tween<Offset>(begin: widget.slideOffset, end: Offset.zero)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeOutCubic))).toList();

    // Staggered start — cap delay at index 6 to avoid long waits
    for (int i = 0; i < count; i++) {
      final delay = widget.itemDelay * i.clamp(0, 6);
      Future.delayed(delay, () {
        if (mounted) _controllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(widget.children.length, (i) =>
        FadeTransition(
          opacity: _fades[i],
          child: SlideTransition(
            position: _slides[i],
            child: widget.children[i],
          ),
        )),
    );
  }
}
```

```dart
// Usage in home_page.dart — wrap challenge cards or notification list
StaggeredList(
  children: provider.notifications
      .map((n) => NotificationTile(notification: n))
      .toList(),
)
```

## Horizontal Stagger for Course Section

```dart
// For horizontal ListView, use AnimatedOpacity + Transform.translate
class StaggeredHorizontalItem extends StatelessWidget {
  final Widget child;
  final int index;
  final Animation<double> animation;

  const StaggeredHorizontalItem({
    super.key,
    required this.child,
    required this.index,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, _) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(20 * (1 - animation.value), 0),
          child: child,
        ),
      ),
    );
  }
}
```

## Incorrect Implementation

```dart
// Anti-pattern: Timer-based animation (unpredictable, not testable)
Timer.periodic(Duration(milliseconds: 50), (timer) {
  setState(() { _visibleCount++; }); // ❌
});

// Anti-pattern: no stagger (all items appear simultaneously — jarring)
ListView.builder(
  itemBuilder: (_, i) => FadeIn(child: items[i]), // ❌ no stagger
);
```
