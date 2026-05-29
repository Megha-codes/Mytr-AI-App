import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class XPProgressBar extends StatelessWidget {
  final int currentXP;
  final int targetXP;
  final String? label;

  const XPProgressBar({
    super.key,
    required this.currentXP,
    required this.targetXP,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (currentXP / targetXP).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(label!, style: AppTheme.labelSmall.copyWith(color: AppTheme.textOnDark)),
          ),
        Container(
          height: 8,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.xpGradientStart, AppTheme.xpGradientEnd],
                ),
                borderRadius: BorderRadius.circular(AppTheme.pillRadius),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class LevelBadge extends StatelessWidget {
  final int level;
  final String title;
  final Color accentColor;

  const LevelBadge({
    super.key,
    required this.level,
    required this.title,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Lvl $level · $title',
            style: AppTheme.labelLarge.copyWith(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: AppTheme.labelSmall,
      ),
    );
  }
}

