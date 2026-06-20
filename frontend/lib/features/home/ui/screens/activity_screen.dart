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
import '../../providers/providers.dart';
import '../../../profile/providers/goals_provider.dart';
import '../widgets/activity_widgets.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(activityProvider);
    final sleep = ref.watch(sleepProvider);
    final deviceState = ref.watch(deviceProvider);
    final stepGoal = (ref.watch(goalsProvider).valueOrNull ?? const Goals()).dailyStepGoal;

    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(activityProvider);
          await ref.read(activityProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: activityAsync.when(
            data: (activity) => _buildContent(context, activity, sleep, deviceState, stepGoal),
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

  Widget _buildContent(BuildContext context, ActivityState activity, SleepState sleep, DeviceState deviceState, int stepGoal) {
    final stepsPercent = stepGoal == 0 ? 0.0 : (activity.stepsToday / stepGoal).clamp(0, 1).toDouble();

    return Column(
      children: [
        const DarkHeader(
          eyebrow: 'ACTIVITY',
          eyebrowColor: AppTheme.brandGreen,
          title: 'Move & track',
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
          child: Transform.translate(
            offset: const Offset(0, -20),
            child: StepsStrip(
              steps: activity.stepsToday,
              goal: stepGoal,
              percent: stepsPercent,
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
                    child: StatTile(
                      label: 'Calories',
                      value: '${activity.caloriesBurned}',
                      textColor: AppTheme.accentOrange,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Active',
                      value: '${activity.activeMinutes}',
                      unit: 'min',
                      textColor: AppTheme.accentCyan,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Heart Rate',
                      value: '${activity.heartRate}',
                      unit: 'bpm',
                      textColor: AppTheme.glucoseHyper,
                      backgroundColor: Colors.white,
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

              if (sleep.hasData)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Sleep last night', style: AppTheme.titleLarge),
                          Text('${sleep.lastNightHours}h', style: AppTheme.displayMedium.copyWith(color: AppTheme.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SleepStageBar(stages: sleep.stages),
                    ],
                  ),
                ),

              if (sleep.hasData) const SizedBox(height: 16),

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
            onPressed: () => context.push('/profile'),
            icon: const Icon(LucideIcons.chevronRight, color: AppTheme.accentCyan),
          ),
        ],
      ),
    );
  }
}
