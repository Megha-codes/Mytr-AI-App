import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/dark_header.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/stat_widgets.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../core/widgets/state_feedback_widgets.dart';
import '../../models/analytics_models.dart';
import '../../providers/analytics_provider.dart';
import '../widgets/analytics_widgets.dart';

/// The Phase-1 polish part-2 analytics screen: glucose TIR/trend/GMI, the
/// food-glucose correlation feature (the lead differentiator — placed
/// right under Insights, before the rest), health trends, and calorie
/// trends over the past week. Always reachable via push (see the entry
/// points on glucose_screen.dart / activity_screen.dart), so it always
/// has a real back target.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(analyticsProvider);
          await ref.read(analyticsProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: analyticsAsync.when(
            data: (analytics) => _buildContent(context, analytics),
            loading: () => const _AnalyticsLoadingView(),
            error: (e, _) => Center(
              child: InlineErrorCard(
                message: 'Failed to load analytics',
                onRetry: () => ref.invalidate(analyticsProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WeeklyAnalytics analytics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DarkHeader(
          eyebrow: 'ANALYTICS',
          eyebrowColor: AppTheme.brandGreen,
          title: 'Your week',
          trailing: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: AppTheme.textOnDark),
            onPressed: () => context.pop(),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(AppTheme.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (analytics.insights.isNotEmpty) ...[
                Text('Insights', style: AppTheme.titleLarge),
                const SizedBox(height: 12),
                for (final insight in analytics.insights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InsightCard(insight: insight),
                  ),
                const SizedBox(height: 24),
              ],

              // ── Food → Glucose (lead feature — prominent, right after
              // insights, ahead of the rest of the glucose breakdown) ──
              Text('Food → Glucose', style: AppTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'How your meals affected your glucose this week',
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              if (analytics.foodGlucoseCorrelations.isEmpty)
                const NotEnoughDataCard(
                  metricLabel: 'Food-glucose correlation',
                  reason: 'Log meals and keep your CGM connected — once a meal has a '
                      'reading before and after it, it shows up here.',
                )
              else
                for (final correlation in analytics.foodGlucoseCorrelations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FoodGlucoseCorrelationCard(correlation: correlation),
                  ),

              const SizedBox(height: 24),

              // ── Glucose ──────────────────────────────────────────────
              Text('Glucose', style: AppTheme.titleLarge),
              const SizedBox(height: 12),
              AppCard(
                child: !analytics.glucose.hasData
                    ? const NotEnoughDataCard(
                        metricLabel: 'Glucose',
                        reason: 'Connect a CGM or log readings manually to see your '
                            'time-in-range and trend here.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Average',
                                  value: '${analytics.glucose.averageMgdl!.round()}',
                                  unit: 'mg/dL',
                                  textColor: AppTheme.brandGreen,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: StatTile(
                                  label: 'GMI (est.)',
                                  value: analytics.glucose.gmiPercent!.toStringAsFixed(1),
                                  unit: '%',
                                  textColor: AppTheme.accentCyan,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (analytics.glucose.tir != null)
                            TIRDonutChart(tir: analytics.glucose.tir!),
                          const SizedBox(height: 20),
                          Text('Daily average', style: AppTheme.labelLarge.copyWith(color: AppTheme.textPrimary)),
                          const SizedBox(height: 12),
                          GlucoseWeekLineChart(daily: analytics.glucose.daily),
                        ],
                      ),
              ),

              const SizedBox(height: 24),

              // ── Health trends ────────────────────────────────────────
              Text('Health trends', style: AppTheme.titleLarge),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MetricTrendMiniChart(
                      label: 'Steps',
                      trend: analytics.healthTrends.steps,
                      color: AppTheme.accentOrange,
                      formatValue: (v) => '${v.round()}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricTrendMiniChart(
                      label: 'Sleep',
                      trend: analytics.healthTrends.sleepMinutes,
                      color: AppTheme.accentCyan,
                      formatValue: (v) => '${(v / 60).toStringAsFixed(1)}h',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MetricTrendMiniChart(
                      label: 'HRV',
                      trend: analytics.healthTrends.hrv,
                      color: AppTheme.brandGreen,
                      formatValue: (v) => '${v.round()} ms',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricTrendMiniChart(
                      label: 'Resting HR',
                      trend: analytics.healthTrends.restingHeartRate,
                      color: AppTheme.glucoseHyper,
                      formatValue: (v) => '${v.round()} bpm',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MetricTrendMiniChart(
                      label: 'Water',
                      trend: analytics.healthTrends.waterMl,
                      color: AppTheme.accentCyan,
                      formatValue: (v) => '${(v / 1000).toStringAsFixed(1)}L',
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ),

              const SizedBox(height: 24),

              // ── Calorie / macro trend ────────────────────────────────
              Text('Calories', style: AppTheme.titleLarge),
              const SizedBox(height: 12),
              AppCard(
                child: CalorieWeekBarChart(daily: analytics.nutritionTrends.daily),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalyticsLoadingView extends StatelessWidget {
  const _AnalyticsLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        CardShimmer(height: 140),
        Padding(
          padding: EdgeInsets.all(AppTheme.screenPadding),
          child: Column(
            children: [
              CardShimmer(height: 120),
              SizedBox(height: 16),
              CardShimmer(height: 260),
              SizedBox(height: 16),
              CardShimmer(height: 180),
            ],
          ),
        ),
      ],
    );
  }
}
