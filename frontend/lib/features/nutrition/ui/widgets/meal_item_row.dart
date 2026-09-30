import 'package:flutter/material.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';

/// One detected food, "YOUR MEAL" card row. Portion is shown as free text
/// ("1.0 x cup") since that's the only shape the backend actually
/// preserves per item — the Gemini-estimated grams get scaled into real
/// numbers server-side, but the human-readable portion phrase from
/// analyze-image (FoodItem.portion) is what's shown here, matching the
/// reference's "1.0 X CUP" / "1.0 X SMALL (6 CM DIA)" style.
class MealItemRow extends StatelessWidget {
  final String name;
  final String portionLabel;
  final bool nutritionVerified;
  final VoidCallback? onTap;

  const MealItemRow({
    super.key,
    required this.name,
    required this.portionLabel,
    required this.nutritionVerified,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.utensils, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name.toUpperCase(),
                          style: AppTheme.labelLarge.copyWith(color: Colors.white, fontSize: 13, fontStyle: FontStyle.italic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!nutritionVerified) ...[
                        const SizedBox(width: 8),
                        const _EstimateTag(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    portionLabel.toUpperCase(),
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.textOnDarkMuted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(LucideIcons.chevronRight, color: AppTheme.textOnDarkMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

/// The safety-relevant tag: a Gemini guess with no database match, so a
/// user can never mistake it for a verified value. Deliberately small and
/// neutral (not alarming — an amber/orange "warning" treatment would
/// overstate what this is: a rough estimate, not a data-quality problem
/// the user needs to act on).
class _EstimateTag extends StatelessWidget {
  const _EstimateTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'ESTIMATED',
        style: AppTheme.labelSmall.copyWith(color: AppTheme.textOnDarkMuted, fontSize: 8, letterSpacing: 0.5),
      ),
    );
  }
}
