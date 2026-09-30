import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../models/food_models.dart';

/// The meal->glucose response section. Real readings only — [hasData]
/// false renders a clean empty state (no CGM connected, or nothing has
/// landed yet), never a fabricated graph.
class MealGlucoseResponseCard extends StatelessWidget {
  final MealGlucoseResponse response;
  final DateTime mealTime;

  const MealGlucoseResponseCard({super.key, required this.response, required this.mealTime});

  @override
  Widget build(BuildContext context) {
    if (!response.hasData) return const _NoGlucoseDataCard();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_headline(response.outcome), style: AppTheme.titleMedium.copyWith(color: Colors.white, fontSize: 17)),
          const SizedBox(height: 12),
          Text(_descriptiveSentence(response), style: AppTheme.bodyMedium.copyWith(color: Colors.white, height: 1.4)),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: _ResponseChart(response: response, mealTime: mealTime),
          ),
        ],
      ),
    );
  }

  // Headline color/text keyed off the real classification the post-meal
  // Celery task computed (meal_logs.glucose_outcome) — descriptive, not a
  // grade: it names what happened, doesn't tell the user what to do
  // about it.
  static String _headline(String? outcome) => switch (outcome) {
        'IN_RANGE' => 'Stable Response',
        'HIGH' => 'Elevated Response',
        'HYPER' => 'High Response',
        'LOW' => 'Low Response',
        'HYPO' => 'Very Low Response',
        _ => 'Glucose Response',
      };

  static String _descriptiveSentence(MealGlucoseResponse r) {
    if (r.deltaMgdl == null || r.outcome == null) {
      return 'Readings are still coming in for this meal.';
    }
    final delta = r.deltaMgdl!;
    final direction = delta > 0 ? 'rose' : (delta < 0 ? 'fell' : 'stayed flat');
    final magnitude = delta.abs();
    final windowLabel = r.postMealWindow == '2hr' ? '2 hours' : '1 hour';

    final rangePhrase = switch (r.outcome) {
      'IN_RANGE' => 'you remained in range after the meal',
      'HIGH' => 'you moved above your target range',
      'HYPER' => 'you moved well above your target range',
      'LOW' => 'you dipped below your target range',
      'HYPO' => 'you dropped well below your target range',
      _ => 'here is how your glucose changed',
    };

    final sizeWord = magnitude < 15 ? 'minimal' : (magnitude < 40 ? 'a moderate' : 'a large');
    return 'This meal caused $sizeWord glucose change ($magnitude mg/dL $direction over $windowLabel) and $rangePhrase.';
  }
}

class _NoGlucoseDataCard extends StatelessWidget {
  const _NoGlucoseDataCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSurface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.activity, color: AppTheme.textHint, size: 28),
          const SizedBox(height: 12),
          Text('No glucose response yet', style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'Connect a CGM to see how your meals affect your glucose.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ResponseChart extends StatelessWidget {
  final MealGlucoseResponse response;
  final DateTime mealTime;

  const _ResponseChart({required this.response, required this.mealTime});

  @override
  Widget build(BuildContext context) {
    final readings = response.readings;
    // Index of the first reading at/after meal_time — splits the line into
    // a muted "before" segment and a real "response" segment, and is where
    // the meal marker sits. Falls back to the whole line being "response"
    // if every reading is already post-meal.
    var mealIndex = readings.indexWhere((r) => !r.recordedAt.isBefore(mealTime));
    if (mealIndex == -1) mealIndex = 0;

    final values = readings.map((r) => r.valueMgdl.toDouble()).toList();
    final minY = (values.reduce((a, b) => a < b ? a : b) - 20).clamp(40, 400).toDouble();
    final maxY = (values.reduce((a, b) => a > b ? a : b) + 20).clamp(40, 400).toDouble();

    final responseColor = _outcomeColor(response.outcome);

    final beforeSpots = [for (var i = 0; i <= mealIndex; i++) FlSpot(i.toDouble(), values[i])];
    final afterSpots = [for (var i = mealIndex; i < values.length; i++) FlSpot(i.toDouble(), values[i])];

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: ((maxY - minY) / 4).clamp(10, 100),
              getTitlesWidget: (value, meta) => Text(
                value.round().toString(),
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textOnDarkMuted, fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (values.length / 4).clamp(1, values.length.toDouble()),
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= readings.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _timeLabel(readings[i].recordedAt),
                    style: AppTheme.labelSmall.copyWith(color: AppTheme.textOnDarkMuted, fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        rangeAnnotations: (response.targetMin != null && response.targetMax != null)
            ? RangeAnnotations(horizontalRangeAnnotations: [
                HorizontalRangeAnnotation(
                  y1: response.targetMin!.toDouble(),
                  y2: response.targetMax!.toDouble(),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ])
            : const RangeAnnotations(),
        lineBarsData: [
          LineChartBarData(
            spots: beforeSpots,
            isCurved: true,
            color: AppTheme.textOnDarkMuted,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: afterSpots,
            isCurved: true,
            color: responseColor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              // Only the meal-time point itself gets a visible marker —
              // matches the reference's single fork/knife dot at the
              // meal, not a dot on every reading.
              getDotPainter: (spot, percent, bar, index) {
                final isMealPoint = spot.x.round() == mealIndex;
                return FlDotCirclePainter(
                  radius: isMealPoint ? 5 : 0,
                  color: responseColor,
                  strokeWidth: isMealPoint ? 2 : 0,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(show: true, color: responseColor.withValues(alpha: 0.08)),
          ),
        ],
      ),
    );
  }

  static Color _outcomeColor(String? outcome) => switch (outcome) {
        'IN_RANGE' => AppTheme.brandGreen,
        'HIGH' => AppTheme.glucoseHigh,
        'HYPER' => AppTheme.glucoseHyper,
        'LOW' => AppTheme.glucoseLow,
        'HYPO' => AppTheme.glucoseHypo,
        _ => AppTheme.brandGreen,
      };

  static String _timeLabel(DateTime t) {
    final local = t.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
