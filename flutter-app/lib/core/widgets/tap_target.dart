import 'package:flutter/widgets.dart';

import 'content_width.dart';

/// Pads [child] out to 44x44 on touch layouts, for the inside of an InkWell or
/// any other detector that is drawn smaller than a finger.
///
/// The desktop layout (rail breakpoint and up) is returned untouched.
class TapTargetBox extends StatelessWidget {
  static const double minSize = 44;

  final Widget child;

  const TapTargetBox({super.key, required this.child});

  static bool applies(BuildContext context) =>
      MediaQuery.sizeOf(context).width < ContentWidth.touchLayoutBelow;

  @override
  Widget build(BuildContext context) {
    if (!applies(context)) return child;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: minSize, minHeight: minSize),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    );
  }
}

/// A tap-only GestureDetector whose hit area is at least 44x44 on touch
/// layouts. The drawn child keeps its size; the padding around it is what
/// takes the tap.
class TapTarget extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const TapTarget({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: TapTargetBox.applies(context)
        ? HitTestBehavior.opaque
        : HitTestBehavior.deferToChild,
    onTap: onTap,
    child: TapTargetBox(child: child),
  );
}
