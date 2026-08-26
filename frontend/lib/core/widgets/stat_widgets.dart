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
              // Expanded + ellipsis: labels are short today ("STEPS",
              // "ACTIVE MINUTES"), but this tile is used 3-across on narrow
              // phones (activity_screen.dart) — an unwrapped Text next to
              // the optional trailing icon is exactly the shape of a
              // RenderFlex horizontal overflow if a longer label ever lands
              // here.
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppTheme.labelSmall.copyWith(color: textColor.withValues(alpha: 0.6)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 4),
                Icon(icon, size: 16, color: textColor.withValues(alpha: 0.6)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: AppTheme.displayMedium.copyWith(color: textColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
            const SizedBox(height: 8),
            MetricHintBox(text: subtext!, color: textColor),
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

/// A subtle, contained box for helper/instruction copy shown under a metric
/// (e.g. "Grant Health permission to see your steps.") — used by
/// [StatTile]'s `subtext` and directly by metric widgets that don't go
/// through StatTile (e.g. StepsStrip in activity_widgets.dart), so this
/// styling only lives in one place.
///
/// This used to just be a bare bodySmall (14px) Text with no cap — on a
/// metric tile narrow enough to sit 3-across (activity_screen.dart) a long
/// message could wrap to half a dozen lines and visually dominate the
/// metric it was meant to annotate. Smaller, capped at 2 lines with an
/// ellipsis, and boxed so it reads as a secondary hint, not competing body
/// text — every call site here pairs with a tap target that shows the full
/// explanation (showConnectDataGuide), so truncation never actually loses
/// the message, just defers it.
class MetricHintBox extends StatelessWidget {
  final String text;
  final Color color;
  final int maxLines;

  const MetricHintBox({
    super.key,
    required this.text,
    required this.color,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: AppTheme.bodySmall.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.25,
          color: color.withValues(alpha: 0.7),
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
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

