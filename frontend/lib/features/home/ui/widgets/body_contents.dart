import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/stat_widgets.dart';
import '../../../../core/widgets/feature_widgets.dart';
import '../../../../core/widgets/progress_widgets.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../core/widgets/state_feedback_widgets.dart';
import '../../providers/providers.dart';
import '../../../profile/providers/goals_provider.dart';

class DiabeticBodyContent extends ConsumerWidget {
  const DiabeticBodyContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insulin = ref.watch(insulinProvider);
    final nutritionAsync = ref.watch(nutritionProvider);
    final challenges = ref.watch(challengesProvider);

    return nutritionAsync.when(
      data: (nutrition) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Bolus Today',
                  value: '${insulin.totalBolusToday}',
                  unit: 'u',
                  backgroundColor: AppTheme.accentCyan,
                  textColor: Colors.white,
                  subtext: '${insulin.adjustmentPercent > 0 ? '+' : ''}${insulin.adjustmentPercent}% adjustment',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatTile(
                  label: 'Calories',
                  value: '${nutrition.caloriesEaten}',
                  backgroundColor: AppTheme.accentOrange,
                  textColor: Colors.white,
                  subtext: 'of ${nutrition.calorieTarget} target',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _ChallengesCard(challenges: challenges),
        ],
      ),
      loading: () => const Column(
        children: [
          Row(
            children: [
              Expanded(child: StatTileShimmer()),
              SizedBox(width: 16),
              Expanded(child: StatTileShimmer()),
            ],
          ),
          SizedBox(height: 24),
          CardShimmer(height: 200),
        ],
      ),
      error: (e, _) => InlineErrorCard(
        message: 'Load error',
        onRetry: () => ref.invalidate(nutritionProvider),
      ),
    );
  }
}

class FitnessBodyContent extends ConsumerWidget {
  const FitnessBodyContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutritionAsync = ref.watch(nutritionProvider);
    final weight = ref.watch(weightProvider);
    final challenges = ref.watch(challengesProvider);
    final goals = ref.watch(goalsProvider).valueOrNull ?? const Goals();

    return nutritionAsync.when(
      data: (nutrition) {
        final calorieTarget = goals.dailyCalorieGoal;
        final caloriesRemaining = (calorieTarget - nutrition.caloriesEaten);
        return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            backgroundColor: AppTheme.accentOrange,
            borderColor: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CALORIE BUDGET', style: AppTheme.labelSmall.copyWith(color: Colors.white.withValues(alpha: 0.7))),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$caloriesRemaining', style: AppTheme.displayLarge.copyWith(color: Colors.white)),
                    Text('REMAINING', style: AppTheme.labelLarge.copyWith(color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${nutrition.caloriesEaten} eaten of $calorieTarget', style: AppTheme.bodySmall.copyWith(color: Colors.white)),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: calorieTarget == 0 ? 0 : (nutrition.caloriesEaten / calorieTarget).clamp(0, 1),
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                ),
                const SizedBox(height: 16),
                Text(
                  'C ${nutrition.carbsEaten.toInt()}g · P ${nutrition.proteinEaten.toInt()}g · F ${nutrition.fatEaten.toInt()}g',
                  style: AppTheme.labelLarge.copyWith(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          if (weight.hasData) ...[
            const SizedBox(height: 24),
            StatTile(
              label: 'Current Weight',
              value: weight.currentWeight.toStringAsFixed(1),
              unit: weight.unit.name.toLowerCase(),
              backgroundColor: AppTheme.accentCyan,
              textColor: Colors.white,
            ),
          ],
          const SizedBox(height: 24),
          _ChallengesCard(challenges: challenges),
        ],
      );
      },
      loading: () => const Column(
        children: [
          CardShimmer(height: 180),
          SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: StatTileShimmer()),
              SizedBox(width: 16),
              Expanded(child: StatTileShimmer()),
            ],
          ),
        ],
      ),
      error: (e, _) => InlineErrorCard(
        message: 'Load error',
        onRetry: () => ref.invalidate(nutritionProvider),
      ),
    );
  }
}

class _ChallengesCard extends StatelessWidget {
  final List<dynamic> challenges;

  const _ChallengesCard({required this.challenges});

  @override
  Widget build(BuildContext context) {
    final completed = challenges.where((c) => c.isCompleted).length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel(text: 'Daily Challenges'),
              TagPill(
                label: '$completed/${challenges.length} · +150 XP',
                backgroundColor: AppTheme.brandGreenLight,
                textColor: AppTheme.brandGreenDark,
              ),
            ],
          ),
          ...challenges.take(3).map((c) => ChallengeRow(
            title: c.title,
            xpReward: c.xpReward,
            isCompleted: c.isCompleted,
          )),
        ],
      ),
    );
  }
}
