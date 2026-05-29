import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../models/models.dart';

class GlucoseZoneLegend extends StatelessWidget {
  final int currentGlucose;
  final double targetMin;
  final double targetMax;

  const GlucoseZoneLegend({
    super.key,
    required this.currentGlucose,
    required this.targetMin,
    required this.targetMax,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildZoneTile('HYPER', '> 250', AppTheme.glucoseHyper, currentGlucose > 250),
        const SizedBox(width: 8),
        _buildZoneTile('HIGH', '${targetMax.toInt()} - 250', AppTheme.glucoseHigh, currentGlucose > targetMax && currentGlucose <= 250),
        const SizedBox(width: 8),
        _buildZoneTile('TARGET', '${targetMin.toInt()} - ${targetMax.toInt()}', AppTheme.glucoseTarget, currentGlucose >= targetMin && currentGlucose <= targetMax),
        const SizedBox(width: 8),
        _buildZoneTile('LOW', '< ${targetMin.toInt()}', AppTheme.glucoseLow, currentGlucose < targetMin),
      ],
    );
  }

  Widget _buildZoneTile(String label, String range, Color color, bool isActive) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? color : AppTheme.borderLight,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(label, style: AppTheme.labelSmall.copyWith(fontSize: 8, color: isActive ? color : AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Text(range, style: AppTheme.labelLarge.copyWith(fontSize: 10, color: isActive ? color : AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class GlucoseChart24h extends StatelessWidget {
  final List<GlucosePoint> data;
  final List<DateTime> mealTimes;

  const GlucoseChart24h({super.key, required this.data, required this.mealTimes});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: CustomPaint(
        painter: _GlucoseChartPainter(data: data, mealTimes: mealTimes),
      ),
    );
  }
}

class _GlucoseChartPainter extends CustomPainter {
  final List<GlucosePoint> data;
  final List<DateTime> mealTimes;

  _GlucoseChartPainter({required this.data, required this.mealTimes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;

    // Draw Zones (Background)
    final targetTop = size.height * 0.4;
    final targetBottom = size.height * 0.7;

    // Above Target
    paint.color = AppTheme.glucoseHigh.withValues(alpha: 0.05);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, targetTop), paint);

    // Target
    paint.color = AppTheme.brandGreen.withValues(alpha: 0.05);
    canvas.drawRect(Rect.fromLTRB(0, targetTop, size.width, targetBottom), paint);

    // Below Target
    paint.color = AppTheme.glucoseLow.withValues(alpha: 0.05);
    canvas.drawRect(Rect.fromLTRB(0, targetBottom, size.width, size.height), paint);

    if (data.isEmpty) return;

    // Draw Line
    final linePaint = Paint()
      ..color = AppTheme.textPrimary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final stepX = size.width / (data.length - 1);
    
    // Normalize values (Assuming range 40 - 300)
    double getY(double value) {
      const minV = 40.0;
      const maxV = 300.0;
      final percent = (value - minV) / (maxV - minV);
      return size.height - (percent * size.height);
    }

    path.moveTo(size.width, getY(data.first.value));
    for (int i = 1; i < data.length; i++) {
      path.lineTo(size.width - (i * stepX), getY(data[i].value));
    }

    canvas.drawPath(path, linePaint);

    // Draw Meal Markers
    final markerPaint = Paint()..style = PaintingStyle.fill;
    final now = DateTime.now();
    for (final mealTime in mealTimes) {
      final diffMin = now.difference(mealTime).inMinutes;
      if (diffMin <= 24 * 60) {
        final x = size.width - (diffMin / (24 * 60) * size.width);
        // Find approximate Y at this X? For now just place on the line if possible, or at bottom.
        // Let's place at a fixed Y for simplicity in mock.
        markerPaint.color = AppTheme.accentOrange;
        canvas.drawCircle(Offset(x, size.height - 10), 4, markerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class TIRStackedBar extends StatelessWidget {
  final TIRBreakdown breakdown;

  const TIRStackedBar({super.key, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                if (breakdown.above > 0)
                  Expanded(flex: (breakdown.above * 100).toInt(), child: Container(color: AppTheme.glucoseHigh)),
                if (breakdown.target > 0)
                  Expanded(flex: (breakdown.target * 100).toInt(), child: Container(color: AppTheme.brandGreen)),
                if (breakdown.below > 0)
                  Expanded(flex: (breakdown.below * 100).toInt(), child: Container(color: AppTheme.glucoseLow)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildStat('High', breakdown.above, AppTheme.glucoseHigh),
            _buildStat('In Range', breakdown.target, AppTheme.brandGreen),
            _buildStat('Low', breakdown.below, AppTheme.glucoseLow),
          ],
        ),
      ],
    );
  }

  Widget _buildStat(String label, double fraction, Color color) {
    return Column(
      children: [
        Text('${(fraction * 100).toInt()}%', style: AppTheme.titleMedium.copyWith(color: color)),
        Text(label, style: AppTheme.labelSmall),
      ],
    );
  }
}
