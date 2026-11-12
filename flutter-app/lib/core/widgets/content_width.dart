import 'package:flutter/widgets.dart';

/// Centres [child] in a column of [maxWidth] on wide windows.
///
/// Side padding rather than Align + ConstrainedBox: the child keeps the exact
/// constraints it had (a Scaffold body is laid out loose, a bottom bar must not
/// grow to full height), and below [maxWidth] it is returned untouched.
class ContentWidth extends StatelessWidget {
  static const double reading = 760;
  static const double wide = 1180;

  final Widget child;
  final double maxWidth;

  const ContentWidth({super.key, required this.child, this.maxWidth = wide});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final extra = constraints.maxWidth - maxWidth;
      if (!extra.isFinite || extra <= 0) return child;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: extra / 2),
        child: child,
      );
    },
  );
}

int adaptiveColumns(double width) => width >= 1000
    ? 4
    : width >= 680
    ? 3
    : 2;
