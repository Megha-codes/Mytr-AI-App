import 'package:flutter/material.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../home/models/models.dart';

class ProfileSectionHeader extends StatelessWidget {
  final String title;
  const ProfileSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title.toUpperCase(),
        style: AppTheme.labelSmall.copyWith(
          color: AppTheme.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class ProfileRow extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback onTap;
  final Color? titleColor;

  const ProfileRow({
    super.key,
    required this.title,
    this.trailing,
    required this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTheme.bodyLarge.copyWith(color: titleColor ?? AppTheme.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // trailing is often account/device data of unpredictable length
            // (a wearable's own name, a user-typed goal, ...) — Flexible so
            // ANY caller's trailing widget is guaranteed to fit the row
            // instead of only being safe when whoever writes the call site
            // happens to remember to bound it themselves.
            if (trailingWidget != null)
              Flexible(child: trailingWidget)
            else
              const SizedBox.shrink(),
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronRight, size: 16, color: AppTheme.borderDark),
          ],
        ),
      ),
    );
  }
}

class AchievementBadge extends StatelessWidget {
  final Achievement achievement;

  const AchievementBadge({super.key, required this.achievement});

  @override
  Widget build(BuildContext context) {
    final bgColor = _getBgColor();
    final borderColor = _getBorderColor();

    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: achievement.isUnlocked ? bgColor : Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: achievement.isUnlocked ? borderColor : Colors.grey[300]!,
              width: 1.5,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  _emojiFromName(achievement.icon),
                  style: TextStyle(
                    fontSize: 32,
                    color: achievement.isUnlocked ? null : Colors.grey[400],
                  ),
                ),
              ),
              if (!achievement.isUnlocked)
                const Positioned(
                  bottom: 8,
                  right: 8,
                  child: Icon(LucideIcons.lock, size: 14, color: AppTheme.textHint),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          achievement.title,
          style: AppTheme.labelSmall.copyWith(fontSize: 10),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _emojiFromName(String name) {
    return switch (name) {
      'utensils'   => '🍽️',
      'activity'   => '⚡',
      'user-check' => '✅',
      'flame'      => '🔥',
      'heart'      => '❤️',
      'star'       => '⭐',
      'zap'        => '⚡',
      'target'     => '🎯',
      _            => '🏆',
    };
  }

  Color _getBgColor() {
    return switch (achievement.category) {
      'SLEEP' => AppTheme.brandGreenLight,
      'MEAL' => AppTheme.accentCyanLight,
      'STREAK' => AppTheme.accentOrangeLight,
      _ => AppTheme.backgroundCream,
    };
  }

  Color _getBorderColor() {
    return switch (achievement.category) {
      'SLEEP' => AppTheme.brandGreen,
      'MEAL' => AppTheme.accentCyan,
      'STREAK' => AppTheme.accentOrange,
      _ => AppTheme.borderLight,
    };
  }
}
