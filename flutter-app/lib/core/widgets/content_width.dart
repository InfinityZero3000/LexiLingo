import 'package:flutter/widgets.dart';

/// Centres [child] in a column of [maxWidth] on wide windows.
///
/// Side padding rather than Align + ConstrainedBox: the child keeps the exact
/// constraints it had (a Scaffold body is laid out loose, a bottom bar must not
/// grow to full height), and below [maxWidth] it is returned untouched.
class ContentWidth extends StatelessWidget {
  static const double reading = 760;
  static const double wide = 1180;

  /// Below this the app is a touch layout with the bottom bar; from here up it
  /// is the desktop layout with the navigation rail.
  static const double touchLayoutBelow = 840;

  /// Tablet portrait: wider than a phone, narrower than the rail layout.
  static bool isTablet(double width) =>
      width >= 600 && width < touchLayoutBelow;

  final Widget child;
  final double maxWidth;

  const ContentWidth({super.key, required this.child, this.maxWidth = wide});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // A 760 column fills a 768 tablet edge to edge, which is just a
      // stretched phone, so the reading column is narrower there.
      final limit = maxWidth == reading && isTablet(constraints.maxWidth)
          ? 640.0
          : maxWidth;
      final extra = constraints.maxWidth - limit;
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
