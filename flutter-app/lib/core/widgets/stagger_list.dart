import 'package:flutter/material.dart';

/// Wraps a list of widgets with staggered entrance animations.
/// Each child fades in and slides up with a configurable delay per item.
///
/// Usage:
/// ```dart
/// StaggeredList(
///   children: [card1, card2, card3],
/// )
/// ```
class StaggeredList extends StatefulWidget {
  final List<Widget> children;
  final Duration itemDelay;
  final Duration itemDuration;
  final double slideOffset;
  final Axis direction;

  const StaggeredList({
    super.key,
    required this.children,
    this.itemDelay = const Duration(milliseconds: 60),
    this.itemDuration = const Duration(milliseconds: 500),
    this.slideOffset = 24.0,
    this.direction = Axis.vertical,
  });

  @override
  State<StaggeredList> createState() => _StaggeredListState();
}

class _StaggeredListState extends State<StaggeredList>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _fadeAnimations;
  late final List<Animation<Offset>> _slideAnimations;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.children.length,
      (i) => AnimationController(
        vsync: this,
        duration: widget.itemDuration,
      ),
    );

    _fadeAnimations = _controllers.map((c) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOut),
      );
    }).toList();

    _slideAnimations = _controllers.map((c) {
      final dx = widget.direction == Axis.horizontal
          ? widget.slideOffset / 100
          : 0.0;
      final dy = widget.direction == Axis.vertical
          ? widget.slideOffset / 100
          : 0.0;
      return Tween<Offset>(
        begin: Offset(dx, dy),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: c, curve: Curves.easeOutCubic));
    }).toList();

    _startAnimations();
  }

  void _startAnimations() async {
    for (var i = 0; i < _controllers.length; i++) {
      if (i > 0) await Future.delayed(widget.itemDelay * i);
      if (_disposed) return;
      _controllers[i].forward();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(widget.children.length, (i) {
        return SlideTransition(
          position: _slideAnimations[i],
          child: FadeTransition(
            opacity: _fadeAnimations[i],
            child: widget.children[i],
          ),
        );
      }),
    );
  }
}

/// Sliver variant for use inside CustomScrollView.
class SliverStaggeredList extends StatefulWidget {
  final List<Widget> children;
  final Duration itemDelay;
  final Duration itemDuration;
  final double slideOffset;

  const SliverStaggeredList({
    super.key,
    required this.children,
    this.itemDelay = const Duration(milliseconds: 70),
    this.itemDuration = const Duration(milliseconds: 480),
    this.slideOffset = 28.0,
  });

  @override
  State<SliverStaggeredList> createState() => _SliverStaggeredListState();
}

class _SliverStaggeredListState extends State<SliverStaggeredList>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _fadeAnimations;
  late final List<Animation<Offset>> _slideAnimations;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.children.length,
      (i) => AnimationController(
        vsync: this,
        duration: widget.itemDuration,
      ),
    );

    _fadeAnimations = _controllers.map((c) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOut),
      );
    }).toList();

    _slideAnimations = _controllers.map((c) {
      return Tween<Offset>(
        begin: Offset(0, widget.slideOffset / 100),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: c, curve: Curves.easeOutCubic));
    }).toList();

    _startAnimations();
  }

  void _startAnimations() async {
    for (var i = 0; i < _controllers.length; i++) {
      if (i > 0) await Future.delayed(widget.itemDelay * i);
      if (_disposed) return;
      _controllers[i].forward();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => SlideTransition(
          position: _slideAnimations[i],
          child: FadeTransition(
            opacity: _fadeAnimations[i],
            child: widget.children[i],
          ),
        ),
        childCount: widget.children.length,
      ),
    );
  }
}
