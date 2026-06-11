import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/dark_header.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/state_feedback_widgets.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../profile/providers/user_profile_provider.dart';
import '../../../profile/providers/goals_provider.dart';
import '../../../profile/ui/screens/goals_screen.dart';
import '../../providers/providers.dart';
import '../widgets/coach_widgets.dart';

class CoachScreen extends ConsumerWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);
    final coachAsync = ref.watch(coachProvider);

    return userAsync.when(
      data: (user) {
        final isDiabetic = user.userType != UserType.fitness;
        return Scaffold(
          backgroundColor: AppTheme.backgroundCream,
          body: RefreshIndicator(
            onRefresh: () => ref.read(coachProvider.notifier).refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  DarkHeader(
                    eyebrow: 'YOUR COACH',
                    eyebrowColor: isDiabetic ? AppTheme.accentCyan : AppTheme.brandGreen,
                    title: isDiabetic ? 'Insulin pathway' : 'Body goals',
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
                    child: Transform.translate(
                      offset: const Offset(0, -30),
                      child: _buildLevelCard(user, isDiabetic),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 0, AppTheme.screenPadding, AppTheme.screenPadding),
                    child: coachAsync.when(
                      data: (coach) => isDiabetic
                          ? _DiabeticCoachContent(coach: coach)
                          : _FitnessCoachContent(coach: coach, user: user),
                      loading: () => const ListShimmer(count: 3),
                      error: (e, _) => Center(
                        child: InlineErrorCard(
                          message: 'Coach offline',
                          onRetry: () => ref.invalidate(coachProvider),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildLevelCard(UserProfile user, bool isDiabetic) {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: isDiabetic ? AppTheme.accentCyan : AppTheme.accentOrange,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text('${user.currentLevel}', style: AppTheme.displayLarge.copyWith(color: Colors.white)),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.levelTitle, style: AppTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text('${user.currentXP} / ${user.xpToNextLevel} XP', style: AppTheme.labelSmall),
                    const SizedBox(height: 12),
                    _XPProgressBar(current: user.currentXP, target: user.xpToNextLevel),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          LevelProgressionStrip(currentLevel: user.currentLevel),
        ],
      ),
    );
  }
}

class _XPProgressBar extends StatelessWidget {
  final int current;
  final int target;
  const _XPProgressBar({required this.current, required this.target});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 8,
          width: double.infinity,
          decoration: BoxDecoration(color: AppTheme.backgroundCream, borderRadius: BorderRadius.circular(4)),
        ),
        FractionallySizedBox(
          widthFactor: (current / target).clamp(0.0, 1.0),
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.brandGreen, AppTheme.accentCyan]),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiabeticCoachContent extends ConsumerWidget {
  final CoachState coach;
  const _DiabeticCoachContent({required this.coach});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cgm = ref.watch(deviceProvider).connectedCGM;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (coach.morningBriefing.isNotEmpty) ...[
          AppCard(
            backgroundColor: AppTheme.accentCyanLight,
            borderColor: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('THIS MORNING', style: AppTheme.labelSmall),
                const SizedBox(height: 8),
                Text(coach.morningBriefing, style: AppTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Insulin reduction pathway', style: AppTheme.titleLarge),
              const SizedBox(height: 24),
              ...coach.insights.map((insight) => InsulinReductionCard(insight: insight)),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Combined potential', style: AppTheme.labelLarge),
                  Text('-${_calculateTotalPotential().toStringAsFixed(1)}u/day', style: AppTheme.titleLarge.copyWith(color: AppTheme.brandGreen)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (coach.todayFocus.isNotEmpty) ...[
          AppCard(
            backgroundColor: AppTheme.backgroundDark,
            borderColor: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Today's focus", style: TextStyle(color: AppTheme.brandGreen, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(coach.todayFocus, style: AppTheme.bodyMedium.copyWith(color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (cgm != null)
          SensorAlertCard(
            deviceName: cgm.name,
            daysRemaining: cgm.daysRemaining,
            onOrderReplacement: () {},
          ),
      ],
    );
  }

  double _calculateTotalPotential() {
    return coach.insights.fold(0.0, (sum, i) => sum + i.estimatedSavingUnits);
  }
}

class _FitnessCoachContent extends ConsumerWidget {
  final CoachState coach;
  final UserProfile user;

  const _FitnessCoachContent({required this.coach, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weight = ref.watch(weightProvider);
    final goals = ref.watch(goalsProvider).valueOrNull ?? const Goals();
    final hasGoal = goals.weightGoalKg != null && weight.hasData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text('⚖️', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text('Weight journey', style: AppTheme.titleLarge),
                    ],
                  ),
                  if (hasGoal)
                    GestureDetector(
                      onTap: () => showGoalSettingSheet(context, ref),
                      child: Text('Edit', style: AppTheme.labelSmall.copyWith(color: AppTheme.accentCyan)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (hasGoal)
                WeightJourneyCard(
                  start: weight.currentWeight,
                  now: weight.currentWeight,
                  goal: goals.weightGoalKg!,
                )
              else
                _SetGoalPrompt(
                  message: weight.hasData
                      ? 'Set a target weight to track your progress.'
                      : 'Add your weight during onboarding, then set a goal.',
                  onTap: () => showGoalSettingSheet(context, ref),
                ),
            ],
          ),
        ),

        if (coach.morningBriefing.isNotEmpty) ...[
          const SizedBox(height: 16),
          AppCard(
            backgroundColor: AppTheme.brandGreenLight,
            borderColor: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('💡', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 8),
                    Text('Pattern detected', style: TextStyle(color: AppTheme.brandGreenDark, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(coach.morningBriefing, style: AppTheme.bodyMedium.copyWith(color: AppTheme.brandGreenDark)),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("This week's targets", style: AppTheme.titleLarge),
              const SizedBox(height: 24),
              ...coach.targets.map((t) => WeeklyTargetRow(target: t)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Achievements', style: AppTheme.titleLarge),
                  GestureDetector(
                    onTap: () {},
                    child: const Text('See all', style: TextStyle(color: AppTheme.accentCyan, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AchievementsRow(achievements: user.recentAchievements),
            ],
          ),
        ),
      ],
    );
  }
}

class _SetGoalPrompt extends StatelessWidget {
  final String message;
  final VoidCallback onTap;
  const _SetGoalPrompt({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: AppTheme.bodySmall),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.brandGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: const Text('Set your goal', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
