import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/stat_widgets.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../core/widgets/state_feedback_widgets.dart';
import '../../../../core/health/metric_copy.dart';
import '../../../wearables/ui/widgets/connect_data_guide_sheet.dart';
import '../../providers/providers.dart';

class DiabeticHeaderContent extends ConsumerWidget {
  const DiabeticHeaderContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cgmAsync = ref.watch(cgmProvider);

    return cgmAsync.when(
      data: (cgm) => _buildContent(cgm),
      loading: () => const CardShimmer(height: 140),
      error: (e, _) => InlineErrorCard(
        message: e.toString(),
        onRetry: () => ref.invalidate(cgmProvider),
      ),
    );
  }

  Widget _buildContent(CGMState cgm) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.cardPadding),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppTheme.brandGreen, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text('LIVE GLUCOSE', style: AppTheme.labelSmall.copyWith(color: AppTheme.textOnDarkMuted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${cgm.currentGlucose}', style: AppTheme.displayLarge.copyWith(color: Colors.white)),
                      const SizedBox(width: 8),
                      Text(cgm.trendArrow, style: AppTheme.displayMedium.copyWith(color: AppTheme.brandGreen)),
                    ],
                  ),
                  Text('${cgm.lastUpdatedMinutesAgo} min ago', style: AppTheme.bodySmall.copyWith(color: AppTheme.textOnDarkMuted)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('TIR 24H', style: AppTheme.labelSmall.copyWith(color: AppTheme.textOnDarkMuted)),
                  const SizedBox(height: 4),
                  Text('${cgm.timeInRange24h.toInt()}%', style: AppTheme.displayMedium.copyWith(color: AppTheme.brandGreen)),
                  const SizedBox(height: 8),
                  TagPill(
                    label: cgm.currentStatus.name.toUpperCase(),
                    backgroundColor: AppTheme.brandGreen.withValues(alpha: 0.2),
                    textColor: AppTheme.brandGreen,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Mini Sparkline Placeholder
          Container(
            height: 40,
            width: double.infinity,
            color: Colors.white.withValues(alpha: 0.02),
            child: Center(
              child: Text('SPARKLINE CHART', style: AppTheme.labelSmall.copyWith(fontSize: 8)),
            ),
          ),
        ],
      ),
    );
  }
}

class FitnessHeaderContent extends ConsumerWidget {
  const FitnessHeaderContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sourced from GET /health/daily (healthDailyProvider), not
    // activityProvider/ActivityState — that path still zero-fills steps/
    // calories in its Hive-cached model (see dashboard_provider.dart), so
    // a metric-aware "no data" state can't be expressed through it without
    // a much larger change to a Hive-persisted type. healthDailyProvider
    // already preserves the null-vs-zero distinction end to end.
    final healthDailyAsync = ref.watch(healthDailyProvider);

    return healthDailyAsync.when(
      data: (healthDaily) => Row(
        children: [
          Expanded(
            child: _metricTile(
              context,
              metric: stepsMetric,
              value: healthDaily.steps,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _metricTile(
              context,
              metric: caloriesMetric,
              value: healthDaily.activeEnergyKcal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            // No real data source exists for active minutes at all (see
            // backend/app/api/dashboard.py) — always the empty state, no
            // tap-through, since nothing the user does would fix it.
            child: StatTile(
              label: activeMinutesMetric.label,
              value: '—',
              subtext: activeMinutesMetric.emptyMessage,
              backgroundColor: AppTheme.backgroundDark.withValues(alpha: 0.5),
              textColor: AppTheme.accentOrange,
            ),
          ),
        ],
      ),
      loading: () => const Row(
        children: [
          Expanded(child: StatTileShimmer()),
          SizedBox(width: 12),
          Expanded(child: StatTileShimmer()),
          SizedBox(width: 12),
          Expanded(child: StatTileShimmer()),
        ],
      ),
      error: (e, _) => InlineErrorCard(
        message: 'Sync error',
        onRetry: () => ref.invalidate(healthDailyProvider),
      ),
    );
  }

  Widget _metricTile(
    BuildContext context, {
    required MetricInfo metric,
    required double? value,
  }) {
    return StatTile(
      label: metric.label,
      value: value != null ? '${value.round()}' : '—',
      subtext: value == null ? metric.emptyMessage : null,
      backgroundColor: AppTheme.backgroundDark.withValues(alpha: 0.5),
      textColor: AppTheme.accentOrange,
      onTap: value == null ? () => showConnectDataGuide(context, highlightMetric: metric) : null,
    );
  }
}
