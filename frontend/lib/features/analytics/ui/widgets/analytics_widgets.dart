import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../models/analytics_models.dart';

/// Every chart here deliberately turns off fl_chart's own axis labels
/// (`titlesData: FlTitlesData(show: false)`) and touch interaction — same
/// choice the one other fl_chart usage in this codebase already makes
/// (features/dashboard/ui/screens/dashboard_screen.dart's sparkline).
/// Day labels are a plain Row of Text below the chart instead (matching
/// the existing hand-rolled WeeklyBarChart's convention), and the actual
/// numbers (average, GMI, etc.) are shown as text elsewhere on the card —
/// these charts are trend *shapes*, not the source of truth for exact
/// values. Keeps the chart config surface small and consistent everywhere
/// it's used, on a library this codebase otherwise has zero real usage of
/// to crib patterns from.

const List<String> _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dayLabel(DateTime date) => _weekdayShort[date.weekday - 1];

/// Shown in place of a chart whenever there isn't enough history to plot
/// honestly — never a chart drawn from near-empty data pretending to be a
/// real trend.
class NotEnoughDataCard extends StatelessWidget {
  final String metricLabel;
  final String reason;

  const NotEnoughDataCard({super.key, required this.metricLabel, this.reason = 'Not enough data yet.'});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.info, size: 18, color: AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              reason,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Time-in-range donut ─────────────────────────────────────────────────

class TIRDonutChart extends StatelessWidget {
  final TIRBreakdown tir;

  const TIRDonutChart({super.key, required this.tir});

  @override
  Widget build(BuildContext context) {
    final sections = <PieChartSectionData>[
      if (tir.above > 0)
        PieChartSectionData(value: tir.above, color: AppTheme.glucoseHigh, showTitle: false, radius: 26),
      if (tir.target > 0)
        PieChartSectionData(value: tir.target, color: AppTheme.brandGreen, showTitle: false, radius: 26),
      if (tir.below > 0)
        PieChartSectionData(value: tir.below, color: AppTheme.glucoseLow, showTitle: false, radius: 26),
    ];

    return Row(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: sections.isEmpty
              ? const SizedBox.shrink()
              : PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 34,
                    sectionsSpace: 2,
                    pieTouchData: PieTouchData(enabled: false),
                  ),
                ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tirLegendRow('In range', tir.target, AppTheme.brandGreen),
              const SizedBox(height: 8),
              _tirLegendRow('High', tir.above, AppTheme.glucoseHigh),
              const SizedBox(height: 8),
              _tirLegendRow('Low', tir.below, AppTheme.glucoseLow),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tirLegendRow(String label, double fraction, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary)),
        const Spacer(),
        Text(
          '${(fraction * 100).round()}%',
          style: AppTheme.labelLarge.copyWith(color: AppTheme.textPrimary),
        ),
      ],
    );
  }
}

// ── Glucose week trend ───────────────────────────────────────────────────

class GlucoseWeekLineChart extends StatelessWidget {
  final List<DailyGlucosePoint> daily;

  const GlucoseWeekLineChart({super.key, required this.daily});

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < daily.length; i++)
        if (daily[i].avgMgdl != null) FlSpot(i.toDouble(), daily[i].avgMgdl!),
    ];

    // Fewer than 2 real points can't show a trend line at all — a single
    // dot isn't a trend, it's just today.
    if (spots.length < 2) {
      return const NotEnoughDataCard(metricLabel: 'Glucose trend');
    }

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              minY: 40,
              maxY: 300,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: AppTheme.brandGreen,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: true, color: AppTheme.brandGreen.withValues(alpha: 0.1)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: daily
              .map((d) => Expanded(
                    child: Text(
                      _dayLabel(d.date),
                      textAlign: TextAlign.center,
                      style: AppTheme.labelSmall.copyWith(
                        color: d.avgMgdl != null ? AppTheme.textPrimary : AppTheme.textHint,
                      ),
                    ),
                  ))
              .toList(),
        ),
        // Known simplification: days with no reading are simply absent
        // from `spots`, so the line visually connects across a gap rather
        // than showing a break — fine for the occasional missed day, but
        // worth revisiting if gaps turn out to be common in practice. The
        // greyed-out label above is the only signal a given day had no
        // real data.
      ],
    );
  }
}

// ── Health metric mini trend (steps / sleep / HRV / resting HR) ─────────

class MetricTrendMiniChart extends StatelessWidget {
  final String label;
  final HealthMetricTrend trend;
  final Color color;
  final String Function(double value) formatValue;

  const MetricTrendMiniChart({
    super.key,
    required this.label,
    required this.trend,
    required this.color,
    required this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    final points = trend.daily.where((p) => p.value != null).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.labelLarge.copyWith(color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          if (points.isEmpty)
            NotEnoughDataCard(metricLabel: label)
          else ...[
            Text(
              formatValue(points.map((p) => p.value!).reduce((a, b) => a + b) / points.length),
              style: AppTheme.titleMedium.copyWith(color: color),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: points.length < 2
                  ? Center(
                      child: Text(
                        'Only ${points.length} day${points.length == 1 ? '' : 's'} so far',
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (var i = 0; i < trend.daily.length; i++)
                                if (trend.daily[i].value != null)
                                  FlSpot(i.toDouble(), trend.daily[i].value!),
                            ],
                            isCurved: true,
                            color: color,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.1)),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Calorie week bars ─────────────────────────────────────────────────────

class CalorieWeekBarChart extends StatelessWidget {
  final List<DailyNutritionPoint> daily;

  const CalorieWeekBarChart({super.key, required this.daily});

  @override
  Widget build(BuildContext context) {
    final withData = daily.where((d) => d.calories != null).toList();
    if (withData.isEmpty) {
      return const NotEnoughDataCard(metricLabel: 'Calories');
    }

    final maxCalories = withData.map((d) => d.calories!).reduce((a, b) => a > b ? a : b).toDouble();

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: BarChart(
            BarChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(enabled: false),
              maxY: maxCalories * 1.2,
              barGroups: [
                for (var i = 0; i < daily.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (daily[i].calories ?? 0).toDouble(),
                        color: daily[i].calories != null
                            ? AppTheme.accentOrange
                            : AppTheme.borderLight,
                        width: 18,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: daily
              .map((d) => Expanded(
                    child: Text(
                      _dayLabel(d.date),
                      textAlign: TextAlign.center,
                      style: AppTheme.labelSmall.copyWith(
                        color: d.calories != null ? AppTheme.textPrimary : AppTheme.textHint,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ── Food -> glucose correlation card (the lead feature) ─────────────────

class FoodGlucoseCorrelationCard extends StatelessWidget {
  final FoodGlucoseCorrelation correlation;

  const FoodGlucoseCorrelationCard({super.key, required this.correlation});

  @override
  Widget build(BuildContext context) {
    final rose = correlation.deltaMgdl >= 0;
    final color = rose ? AppTheme.glucoseHigh : AppTheme.brandGreen;

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(rose ? LucideIcons.arrowUp : LucideIcons.arrowDown, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(correlation.label, style: AppTheme.labelLarge.copyWith(color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '${correlation.baselineMgdl} → ${correlation.postMealMgdl} mg/dL '
                  '(${correlation.window} after)'
                  '${correlation.carbsG != null ? ' · ${correlation.carbsG!.round()}g carbs' : ''}',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${rose ? '+' : ''}${correlation.deltaMgdl}',
            style: AppTheme.titleMedium.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ── Insight card ──────────────────────────────────────────────────────────

class InsightCard extends StatelessWidget {
  final AnalyticsInsight insight;

  const InsightCard({super.key, required this.insight});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      backgroundColor: AppTheme.brandGreenLight,
      borderColor: Colors.transparent,
      child: Row(
        children: [
          const Icon(LucideIcons.sparkles, color: AppTheme.brandGreenDark, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              insight.text,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.brandGreenDark),
            ),
          ),
        ],
      ),
    );
  }
}
