import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/dark_header.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/stat_widgets.dart';
import '../../../../core/widgets/weekly_bar_chart.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../core/widgets/state_feedback_widgets.dart';
import '../../../../core/health/metric_copy.dart';
import '../../providers/providers.dart';
import '../../../profile/providers/goals_provider.dart';
import '../../../profile/providers/user_profile_provider.dart';
import '../../../wearables/services/health_sync_service.dart';
import '../../../wearables/ui/widgets/connect_data_guide_sheet.dart';
import '../widgets/activity_widgets.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(activityProvider);
    final sleep = ref.watch(sleepProvider).valueOrNull ?? SleepState(hasData: false);
    final healthDaily = ref.watch(healthDailyProvider).valueOrNull ?? const HealthDailyState();
    final deviceState = ref.watch(deviceProvider);
    final stepGoal = (ref.watch(goalsProvider).valueOrNull ?? const Goals()).dailyStepGoal;
    // Fitness-type users land here as their default bottom-nav tab (no way
    // back needed — there's nowhere "back" to). Diabetic-type users have no
    // tab of their own for this screen at all; they only ever arrive by
    // pushing in from the "Health & Activity" link on /glucose
    // (glucose_screen.dart), so they need an explicit way back.
    final userType = ref.watch(userProfileProvider).valueOrNull?.userType;
    final showBackButton = userType != null && userType != UserType.fitness;

    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: RefreshIndicator(
        onRefresh: () async {
          // Fire a real health sync before refreshing — pulling down is the
          // one explicit "get me current data" signal a user has here.
          await ref.read(healthSyncServiceProvider).sync();
          ref.invalidate(activityProvider);
          ref.invalidate(sleepProvider);
          ref.invalidate(healthDailyProvider);
          await ref.read(activityProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: activityAsync.when(
            data: (activity) => _buildContent(context, activity, sleep, healthDaily, deviceState, stepGoal, showBackButton),
            loading: () => const _ActivityLoadingView(),
            error: (e, _) => Center(
              child: InlineErrorCard(
                message: 'Failed to load activity',
                onRetry: () => ref.invalidate(activityProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ActivityState activity, SleepState sleep, HealthDailyState healthDaily, DeviceState deviceState, int stepGoal, bool showBackButton) {
    final steps = healthDaily.steps;
    final stepsPercent = stepGoal == 0 || steps == null ? 0.0 : (steps / stepGoal).clamp(0, 1).toDouble();

    return Column(
      children: [
        DarkHeader(
          eyebrow: 'ACTIVITY',
          eyebrowColor: AppTheme.brandGreen,
          title: 'Move & track',
          trailing: showBackButton
              ? IconButton(
                  icon: const Icon(LucideIcons.arrowLeft, color: AppTheme.textOnDark),
                  onPressed: () => context.pop(),
                )
              : null,
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
          child: Transform.translate(
            offset: const Offset(0, -20),
            child: StepsStrip(
              steps: steps?.round(),
              goal: stepGoal,
              percent: stepsPercent,
              onConnect: () => showConnectDataGuide(context, highlightMetric: stepsMetric),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 0, AppTheme.screenPadding, AppTheme.screenPadding),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _healthStatTile(
                      context,
                      metric: caloriesMetric,
                      value: healthDaily.activeEnergyKcal,
                      textColor: AppTheme.accentOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    // No real data source exists for active minutes at all
                    // (see backend/app/api/dashboard.py) — always the empty
                    // state, no tap-through, since nothing the user does
                    // would fix it.
                    child: StatTile(
                      label: activeMinutesMetric.label,
                      value: '—',
                      subtext: activeMinutesMetric.emptyMessage,
                      textColor: AppTheme.accentCyan,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _healthStatTile(
                      context,
                      metric: heartRateMetric,
                      value: healthDaily.heartRate,
                      unit: 'bpm',
                      textColor: AppTheme.glucoseHyper,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Resting HR and HRV come straight from GET /health/daily —
              // "no data" (not 0) when the day has no sample, per
              // docs/health-data-setup.md §2: neither is producible by a
              // phone alone, so the empty state says so specifically
              // rather than a generic "no data yet".
              Row(
                children: [
                  Expanded(
                    child: _healthStatTile(
                      context,
                      metric: restingHeartRateMetric,
                      value: healthDaily.restingHeartRate,
                      unit: 'bpm',
                      textColor: AppTheme.glucoseHyper,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _healthStatTile(
                      context,
                      metric: hrvMetric,
                      value: healthDaily.hrv,
                      unit: 'ms',
                      textColor: AppTheme.brandGreen,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This week\'s steps', style: AppTheme.titleLarge),
                    const SizedBox(height: 24),
                    WeeklyBarChart(
                      data: activity.stepHistory.map((DailyValue v) => WeeklyBarData(
                        day: v.day,
                        value: v.value,
                        isToday: false, // In real app, calculate based on day
                      )).toList(),
                      activeColor: AppTheme.brandGreen,
                      inactiveColor: AppTheme.borderLight,
                      goalLine: stepGoal.toDouble(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Full weekly analytics (Phase-1 polish, part 2) — same
              // destination glucose_screen.dart's more prominent card
              // leads to, reachable from here too since this is where
              // health-trend-minded users already are.
              _AnalyticsLink(onTap: () => context.push('/analytics')),

              const SizedBox(height: 16),

              if (sleep.hasData)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Sleep last night', style: AppTheme.titleLarge),
                          Text('${sleep.lastNightHours.toStringAsFixed(1)}h', style: AppTheme.displayMedium.copyWith(color: AppTheme.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Stage breakdown is local-only (no backend storage for
                      // it — see lastSyncedSleepStagesProvider) and can be
                      // empty even when hasData is true, if no sync has run
                      // yet this session. Fall back to just the total above.
                      if (sleep.stages.isNotEmpty)
                        SleepStageBar(stages: sleep.stages)
                      else
                        Text(
                          'Sync your wearable to see stage breakdown.',
                          style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                )
              else
                // Previously just vanished with no explanation at all when
                // there was no sleep sample — now says specifically why
                // (needs a wearable worn overnight, not a permission gap)
                // and leads somewhere.
                _EmptyMetricCard(metric: sleepMetric, icon: LucideIcons.bedtime),

              const SizedBox(height: 16),

              if (deviceState.connectedWearables.isNotEmpty)
                _SyncPill(device: deviceState.connectedWearables.first)
              else
                _ConnectPrompt(),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ],
    );
  }

  Widget _healthStatTile(
    BuildContext context, {
    required MetricInfo metric,
    required double? value,
    Color textColor = AppTheme.textPrimary,
    String? unit,
  }) {
    return StatTile(
      label: metric.label,
      value: value != null ? '${value.round()}' : '—',
      unit: value != null ? unit : null,
      subtext: value == null ? metric.emptyMessage : null,
      textColor: textColor,
      backgroundColor: Colors.white,
      onTap: value == null ? () => showConnectDataGuide(context, highlightMetric: metric) : null,
    );
  }
}

class _ActivityLoadingView extends StatelessWidget {
  const _ActivityLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        CardShimmer(height: 200),
        Padding(
          padding: EdgeInsets.all(AppTheme.screenPadding),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: StatTileShimmer()),
                  SizedBox(width: 12),
                  Expanded(child: StatTileShimmer()),
                  SizedBox(width: 12),
                  Expanded(child: StatTileShimmer()),
                ],
              ),
              SizedBox(height: 16),
              CardShimmer(height: 300),
            ],
          ),
        ),
      ],
    );
  }
}

class _SyncPill extends StatelessWidget {
  final WearableDevice device;
  const _SyncPill({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.refreshCw, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(
            'Synced from ${device.name}',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsLink extends StatelessWidget {
  final VoidCallback onTap;

  const _AnalyticsLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        child: Row(
          children: [
            const Icon(LucideIcons.sparkles, color: AppTheme.brandGreen),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly analytics', style: AppTheme.labelLarge.copyWith(color: AppTheme.textPrimary)),
                  Text(
                    'Trends, food-glucose correlation, and insights',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ConnectPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      backgroundColor: AppTheme.accentCyan.withValues(alpha: 0.05),
      borderColor: AppTheme.accentCyan.withValues(alpha: 0.2),
      child: Row(
        children: [
          const Icon(LucideIcons.watch, color: AppTheme.accentCyan),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connect a wearable', style: AppTheme.labelLarge.copyWith(color: AppTheme.accentCyan)),
                const Text('Get better activity & sleep data.', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            // Opens the full guidance flow, not just a bare navigation —
            // this is often someone's first "nothing is showing up" moment,
            // and the sync-toggle gotcha (docs/health-data-setup.md §4)
            // belongs right here, not just buried in Manage Devices.
            onPressed: () => showConnectDataGuide(context),
            icon: const Icon(LucideIcons.chevronRight, color: AppTheme.accentCyan),
          ),
        ],
      ),
    );
  }
}

/// A full-card empty state for a metric that deserves more room than a
/// StatTile's subtext — currently just the sleep card, which used to
/// vanish silently with no explanation at all when there was no sample.
class _EmptyMetricCard extends StatelessWidget {
  final MetricInfo metric;
  final IconData icon;

  const _EmptyMetricCard({required this.metric, required this.icon});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metric.label, style: AppTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  metric.emptyMessage,
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (metric.ctaLabel != null)
            IconButton(
              onPressed: () => showConnectDataGuide(context, highlightMetric: metric),
              icon: const Icon(LucideIcons.chevronRight, color: AppTheme.textSecondary),
            ),
        ],
      ),
    );
  }
}
