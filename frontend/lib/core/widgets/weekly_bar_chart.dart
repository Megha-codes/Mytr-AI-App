import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WeeklyBarData {
  final String day;
  final double value;
  final bool isToday;

  WeeklyBarData({required this.day, required this.value, this.isToday = false});
}

class WeeklyBarChart extends StatelessWidget {
  final List<WeeklyBarData> data;
  final Color activeColor;
  final Color inactiveColor;
  final double? goalLine;

  const WeeklyBarChart({
    super.key,
    required this.data,
    required this.activeColor,
    required this.inactiveColor,
    this.goalLine,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 120,
          child: CustomPaint(
            size: Size.infinite,
            painter: _BarChartPainter(
              data: data,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              goalLine: goalLine,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: data.map((d) => Expanded(
            child: Text(
              d.day,
              textAlign: TextAlign.center,
              style: AppTheme.labelSmall.copyWith(
                color: d.isToday ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<WeeklyBarData> data;
  final Color activeColor;
  final Color inactiveColor;
  final double? goalLine;

  _BarChartPainter({
    required this.data,
    required this.activeColor,
    required this.inactiveColor,
    this.goalLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final barWidth = size.width / (data.length * 2);
    final maxVal = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final scale = maxVal == 0 ? 1 : size.height / maxVal;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      final barHeight = d.value * scale * 0.8; // 80% height for padding
      final x = (i * 2 + 0.5) * barWidth;
      final y = size.height - barHeight;

      paint.color = d.isToday ? activeColor : inactiveColor;
      
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(4),
      );

      canvas.drawRRect(rect, paint);

      if (d.isToday) {
        final borderPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawRRect(rect, borderPaint);
      }
    }

    if (goalLine != null) {
      final goalY = size.height - (goalLine! * scale * 0.8);
      final goalPaint = Paint()
        ..color = AppTheme.textSecondary.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;
      
      // Draw dashed line
      double dashWidth = 5, dashSpace = 3, currentX = 0;
      while (currentX < size.width) {
        canvas.drawLine(
          Offset(currentX, goalY),
          Offset(currentX + dashWidth, goalY),
          goalPaint,
        );
        currentX += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

