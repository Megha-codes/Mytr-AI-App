import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

class CgmArcPainter extends CustomPainter {
  final double valueMgdl;
  final double maxMgdl;
  final Color valueColor;

  CgmArcPainter({
    required this.valueMgdl,
    required this.maxMgdl,
    required this.valueColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) - 10; // padding

    // 240 degrees = 4 * pi / 3
    const sweepAngle = 4 * pi / 3;
    // Start at 150 degrees (5 * pi / 6) to be symmetrical
    const startAngle = 5 * pi / 6;

    final trackPaint = Paint()
      ..color = AppColors.darkSurface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    // Draw background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Calculate fill percentage (clamped to 0.0 - 1.0)
    final fillPercent = (valueMgdl / maxMgdl).clamp(0.0, 1.0);
    final fillSweepAngle = sweepAngle * fillPercent;

    final fillPaint = Paint()
      ..color = valueColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    // Draw value arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      fillSweepAngle,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CgmArcPainter oldDelegate) {
    return oldDelegate.valueMgdl != valueMgdl || oldDelegate.valueColor != valueColor;
  }
}
