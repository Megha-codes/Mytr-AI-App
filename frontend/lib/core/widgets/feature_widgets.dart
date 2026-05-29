import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_theme.dart';

class GlucoseZoneLegend extends StatelessWidget {
  final int targetMin;
  final int targetMax;

  const GlucoseZoneLegend({
    super.key,
    required this.targetMin,
    required this.targetMax,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RANGE LEGEND', style: AppTheme.labelSmall),
        const SizedBox(height: 12),
        Row(
          children: [
            _ZoneItem(color: AppTheme.glucoseHyper, label: 'Hyper', range: '>${targetMax + 50}'),
            _ZoneItem(color: AppTheme.glucoseHigh, label: 'High', range: '$targetMax-${targetMax + 50}'),
            _ZoneItem(color: AppTheme.glucoseTarget, label: 'Target', range: '$targetMin-$targetMax'),
            _ZoneItem(color: AppTheme.glucoseLow, label: 'Low', range: '${targetMin - 30}-$targetMin'),
            _ZoneItem(color: AppTheme.glucoseHypo, label: 'Hypo', range: '<${targetMin - 30}'),
          ],
        ),
      ],
    );
  }
}

class _ZoneItem extends StatelessWidget {
  final Color color;
  final String label;
  final String range;

  const _ZoneItem({required this.color, required this.label, required this.range});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: AppTheme.labelSmall.copyWith(fontSize: 8)),
          Text(range, style: AppTheme.bodySmall.copyWith(fontSize: 8)),
        ],
      ),
    );
  }
}

class MacroBar extends StatelessWidget {
  final String label;
  final double current;
  final double target;
  final Color color;

  const MacroBar({
    super.key,
    required this.label,
    required this.current,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (current / target).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTheme.labelLarge.copyWith(fontSize: 12)),
            Text('${current.toInt()}g / ${target.toInt()}g', style: AppTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 6,
          width: double.infinity,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppTheme.pillRadius),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ChallengeRow extends StatelessWidget {
  final String title;
  final int xpReward;
  final bool isCompleted;

  const ChallengeRow({
    super.key,
    required this.title,
    required this.xpReward,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isCompleted ? AppTheme.brandGreen : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: isCompleted ? AppTheme.brandGreen : AppTheme.borderLight,
                width: 1.5,
              ),
            ),
            child: Icon(
              LucideIcons.check,
              size: 14,
              color: isCompleted ? Colors.white : Colors.transparent,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: AppTheme.bodyMedium.copyWith(
                color: isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary,
                decoration: isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '+$xpReward XP',
            style: AppTheme.labelSmall.copyWith(
              color: isCompleted ? AppTheme.textSecondary : AppTheme.brandGreen,
            ),
          ),
        ],
      ),
    );
  }
}

