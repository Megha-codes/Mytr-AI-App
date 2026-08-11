import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;
  final String? subtext;

  /// When set, the whole tile becomes tappable — used for empty-state
  /// tiles that need to lead somewhere (grant permission, connect a
  /// wearable), not for tiles already showing real data.
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.backgroundColor = AppTheme.backgroundWhite,
    this.textColor = AppTheme.textPrimary,
    this.icon,
    this.subtext,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = AppCard(
      backgroundColor: backgroundColor,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTheme.labelSmall.copyWith(color: textColor.withValues(alpha: 0.6)),
              ),
              if (icon != null) Icon(icon, size: 16, color: textColor.withValues(alpha: 0.6)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTheme.displayMedium.copyWith(color: textColor),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: AppTheme.labelLarge.copyWith(color: textColor.withValues(alpha: 0.6)),
                ),
              ],
            ],
          ),
          if (subtext != null) ...[
            const SizedBox(height: 4),
            Text(
              subtext!,
              style: AppTheme.bodySmall.copyWith(color: textColor.withValues(alpha: 0.6)),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: card,
    );
  }
}

class TagPill extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const TagPill({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      ),
      child: Text(
        label,
        style: AppTheme.labelLarge.copyWith(color: textColor, fontSize: 10),
      ),
    );
  }
}

