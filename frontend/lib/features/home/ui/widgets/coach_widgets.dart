import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../models/models.dart';

class LevelProgressionStrip extends StatelessWidget {
  final int currentLevel;

  const LevelProgressionStrip({super.key, required this.currentLevel});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: 6, // 2 before, current, 3 after
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final levelNum = currentLevel - 2 + index;
          if (levelNum <= 0) return const SizedBox.shrink();
          
          final isCompleted = levelNum < currentLevel;
          final isCurrent = levelNum == currentLevel;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isCurrent 
                  ? AppTheme.accentCyan 
                  : (isCompleted ? AppTheme.backgroundDark : Colors.transparent),
              borderRadius: BorderRadius.circular(100),
              border: !isCurrent && !isCompleted 
                  ? Border.all(color: AppTheme.borderLight, style: BorderStyle.solid) 
                  : null,
            ),
            child: Center(
              child: Text(
                'Lvl $levelNum',
                style: AppTheme.labelSmall.copyWith(
                  color: isCurrent || isCompleted ? Colors.white : AppTheme.textSecondary,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class InsulinReductionCard extends StatelessWidget {
  final CoachInsight insight;

  const InsulinReductionCard({super.key, required this.insight});

  @override
  Widget build(BuildContext context) {
    final (bgColor, badgeColor) = _getColors();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(insight.title, style: AppTheme.titleMedium.copyWith(color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(insight.description, style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(8)),
            child: Text(
              '-${insight.estimatedSavingUnits.toStringAsFixed(1)}u/day',
              style: AppTheme.labelLarge.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _getColors() {
    final cat = insight.category.toLowerCase();
    if (cat.contains('sleep')) return (AppTheme.brandGreenLight, AppTheme.brandGreen);
    if (cat.contains('diet') || cat.contains('nutrition')) return (AppTheme.accentOrangeLight, AppTheme.accentOrange);
    if (cat.contains('stress') || cat.contains('mind')) return (AppTheme.accentCyanLight, AppTheme.accentCyan);
    return (AppTheme.brandGreenLight, AppTheme.brandGreen);
  }
}

class WeightJourneyCard extends StatelessWidget {
  final double start;
  final double now;
  final double goal;

  const WeightJourneyCard({super.key, required this.start, required this.now, required this.goal});

  @override
  Widget build(BuildContext context) {
    final totalDiff = (start - goal).abs();
    final currentDiff = (start - now).abs();
    final progress = totalDiff == 0 ? 0.0 : (currentDiff / totalDiff).clamp(0.0, 1.0);
    final percent = (progress * 100).toInt();

    final isOnTrack = now <= start; 

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildWeightPoint('Starting', start),
            _buildWeightPoint('Now', now, isAccent: true),
            _buildWeightPoint('Goal', goal),
          ],
        ),
        const SizedBox(height: 24),
        Stack(
          children: [
            Container(
              height: 8,
              width: double.infinity,
              decoration: BoxDecoration(color: AppTheme.backgroundCream, borderRadius: BorderRadius.circular(4)),
            ),
            FractionallySizedBox(
              widthFactor: progress,
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.brandGreen,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppTheme.accentOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '-${currentDiff.toStringAsFixed(1)} kg of ${totalDiff.toStringAsFixed(1)} kg goal · $percent% done',
          style: AppTheme.bodySmall.copyWith(
            color: isOnTrack ? AppTheme.brandGreen : AppTheme.accentOrange,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildWeightPoint(String label, double val, {bool isAccent = false}) {
    return Column(
      children: [
        Text(label, style: AppTheme.labelSmall),
        Text(val.toStringAsFixed(1), style: AppTheme.titleMedium.copyWith(color: isAccent ? AppTheme.accentOrange : AppTheme.textPrimary)),
        Text('kg', style: AppTheme.bodySmall.copyWith(fontSize: 10)),
      ],
    );
  }
}

class WeeklyTargetRow extends StatelessWidget {
  final CoachInsight target;

  const WeeklyTargetRow({super.key, required this.target});

  @override
  Widget build(BuildContext context) {
    final progress = target.progress.clamp(0.0, 1.0);
    final color = _getColor();
    final daysCompleted = (progress * 7).toInt();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              const Text('🎯', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Text(target.title, style: AppTheme.titleMedium)),
              Text('$daysCompleted/7 days', style: AppTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                height: 6,
                width: double.infinity,
                decoration: BoxDecoration(color: AppTheme.backgroundCream, borderRadius: BorderRadius.circular(3)),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getColor() {
    final cat = target.category.toLowerCase();
    if (cat.contains('step')) return AppTheme.brandGreen;
    if (cat.contains('calor')) return AppTheme.accentOrange;
    if (cat.contains('sleep')) return AppTheme.accentCyan;
    return AppTheme.brandGreen;
  }
}

class AchievementsRow extends StatelessWidget {
  final List<Achievement> achievements;

  const AchievementsRow({super.key, required this.achievements});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: achievements.take(4).map((a) => _AchievementIcon(achievement: a)).toList(),
    );
  }
}

class _AchievementIcon extends StatelessWidget {
  final Achievement achievement;
  const _AchievementIcon({required this.achievement});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(color: AppTheme.backgroundCream, shape: BoxShape.circle),
          child: Center(child: Text(achievement.icon, style: const TextStyle(fontSize: 32))),
        ),
        const SizedBox(height: 8),
        Text(achievement.title, style: AppTheme.labelSmall.copyWith(fontSize: 10)),
      ],
    );
  }
}

class SensorAlertCard extends StatelessWidget {
  final String deviceName;
  final int daysRemaining;
  final VoidCallback onOrderReplacement;

  const SensorAlertCard({
    super.key,
    required this.deviceName,
    required this.daysRemaining,
    required this.onOrderReplacement,
  });

  @override
  Widget build(BuildContext context) {
    final isUrgent = daysRemaining < 2;
    final bgColor = isUrgent ? AppTheme.glucoseLow.withValues(alpha: 0.1) : AppTheme.accentOrangeLight;
    final accentColor = isUrgent ? AppTheme.glucoseLow : AppTheme.accentOrange;

    return AppCard(
      backgroundColor: bgColor,
      borderColor: accentColor.withValues(alpha: 0.2),
      child: Row(
        children: [
          Icon(Icons.sensors, color: accentColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$deviceName · $daysRemaining days remaining',
                  style: AppTheme.labelLarge.copyWith(color: accentColor),
                ),
                GestureDetector(
                  onTap: onOrderReplacement,
                  child: Text(
                    'Order replacement',
                    style: AppTheme.bodySmall.copyWith(
                      decoration: TextDecoration.underline,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
