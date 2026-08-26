import 'dart:math';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Paints the winding bezier path that connects lesson nodes in the roadmap.
///
/// Flat-minimal style: one clean stroke per segment — solid for completed
/// ground already covered, dashed for the road still ahead. No layered
/// glow/shadow strokes, matching the modern-corporate visual direction.
class RoadmapPathPainter extends CustomPainter {
  final List<Offset> nodeCenters;
  final List<Color> segmentColors;
  final List<bool> segmentSolid;
  final double nodeRadius;

  RoadmapPathPainter({
    required this.nodeCenters,
    required this.segmentColors,
    required this.segmentSolid,
    this.nodeRadius = 40.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodeCenters.length < 2) return;

    for (int i = 0; i < nodeCenters.length - 1; i++) {
      final p1 = nodeCenters[i];
      final p2 = nodeCenters[i + 1];

      final color = i < segmentColors.length
          ? segmentColors[i]
          : Colors.grey.withValues(alpha: 0.4);
      final solid = i < segmentSolid.length ? segmentSolid[i] : false;

      _drawSegment(canvas, p1, p2, color, solid);
    }
  }

  void _drawSegment(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color,
    bool solid,
  ) {
    // Connection starts at bottom of first node, ends at top of second node
    final start = Offset(from.dx, from.dy + nodeRadius * 0.85);
    final end = Offset(to.dx, to.dy - nodeRadius * 0.85);

    final gap = end.dy - start.dy;
    final ctrl1 = Offset(from.dx, start.dy + gap * 0.45);
    final ctrl2 = Offset(to.dx, end.dy - gap * 0.45);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(ctrl1.dx, ctrl1.dy, ctrl2.dx, ctrl2.dy, end.dx, end.dy);

    final paint = Paint()
      ..color = color.withValues(alpha: solid ? 0.9 : 0.4)
      ..strokeWidth = solid ? 7 : 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (solid) {
      canvas.drawPath(path, paint);
    } else {
      _drawDashedPath(canvas, path, paint);
    }
  }

  void _drawDashedPath(Canvas canvas, Path src, Paint paint) {
    const dashLength = 7.0;
    const gapLength = 10.0;
    final metrics = src.computeMetrics();

    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final segment = metric.extractPath(
          distance,
          min(distance + dashLength, metric.length),
        );
        canvas.drawPath(segment, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(RoadmapPathPainter oldDelegate) =>
      !listEquals(nodeCenters, oldDelegate.nodeCenters) ||
      !listEquals(segmentColors, oldDelegate.segmentColors) ||
      !listEquals(segmentSolid, oldDelegate.segmentSolid);
}
