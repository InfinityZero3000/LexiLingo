import 'dart:math';
import 'package:flutter/material.dart';

/// Paints the winding bezier path that connects lesson nodes in the roadmap.
///
/// For each pair of consecutive node centers, a cubic bezier is drawn so that
/// the path curves smoothly from one node to the next — exactly like Duolingo's
/// winding snake road.
class RoadmapPathPainter extends CustomPainter {
  final List<Offset> nodeCenters;
  final List<Color> segmentColors;
  final double nodeRadius;

  RoadmapPathPainter({
    required this.nodeCenters,
    required this.segmentColors,
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

      _drawSegment(canvas, p1, p2, color);
    }
  }

  void _drawSegment(Canvas canvas, Offset from, Offset to, Color color) {
    // Connection starts at bottom of first node, ends at top of second node
    final start = Offset(from.dx, from.dy + nodeRadius * 0.85);
    final end = Offset(to.dx, to.dy - nodeRadius * 0.85);

    final gap = end.dy - start.dy;
    final ctrl1 = Offset(from.dx, start.dy + gap * 0.45);
    final ctrl2 = Offset(to.dx, end.dy - gap * 0.45);

    // Thicker outer shadow path (depth effect)
    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final mainPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final highlightPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(ctrl1.dx, ctrl1.dy, ctrl2.dx, ctrl2.dy, end.dx, end.dy);

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, mainPaint);

    // Dash pattern overlay for visual depth
    _drawDashedPath(canvas, path, highlightPaint);
  }

  void _drawDashedPath(Canvas canvas, Path src, Paint paint) {
    const dashLength = 8.0;
    const gapLength = 14.0;
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
      nodeCenters != oldDelegate.nodeCenters ||
      segmentColors != oldDelegate.segmentColors;
}
