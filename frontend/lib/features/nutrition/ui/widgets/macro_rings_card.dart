import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// "MACRO SPLIT" card — big calorie total + 4 macro rings, matching the
/// reference design's dark-card layout (this app's own established dark-
/// chrome-on-cream pattern, see DarkHeader/onboarding's nearBlack cards —
/// not a new visual language, just this screen's use of it).
///
/// Each ring's arc length is that macro's share of THIS meal's own total
/// macro grams (protein+fat+carbs+fiber) — a real, meal-specific
/// proportion, not an arbitrary daily target this app doesn't define
/// per-meal.
class MacroRingsCard extends StatelessWidget {
  final int calories;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double fiberG;

  const MacroRingsCard({
    super.key,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.fiberG,
  });

  @override
  Widget build(BuildContext context) {
    final totalMacroG = proteinG + fatG + carbsG + fiberG;
    double fractionOf(double grams) => totalMacroG <= 0 ? 0 : (grams / totalMacroG).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MACRO SPLIT', style: AppTheme.labelSmall.copyWith(color: AppTheme.textOnDarkMuted)),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Text('$calories', style: AppTheme.displayLarge.copyWith(color: Colors.white, fontSize: 44)),
                Text('Calories', style: AppTheme.bodySmall.copyWith(color: AppTheme.textOnDarkMuted)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              MacroRing(label: 'Protein', grams: proteinG, color: AppTheme.brandPurple, fraction: fractionOf(proteinG)),
              MacroRing(label: 'Fat', grams: fatG, color: AppTheme.textHint, fraction: fractionOf(fatG)),
              MacroRing(label: 'Carbs', grams: carbsG, color: AppTheme.brandRed, fraction: fractionOf(carbsG)),
              MacroRing(label: 'Fiber', grams: fiberG, color: AppTheme.chartTeal, fraction: fractionOf(fiberG)),
            ],
          ),
        ],
      ),
    );
  }
}

class MacroRing extends StatelessWidget {
  final String label;
  final double grams;
  final Color color;
  final double fraction;

  const MacroRing({
    super.key,
    required this.label,
    required this.grams,
    required this.color,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 4,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  value: fraction.clamp(0.03, 1.0), // a sliver stays visible even near-zero
                  strokeWidth: 4,
                  color: color,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(text: '${grams.round()}', style: AppTheme.labelLarge.copyWith(color: color, fontSize: 16)),
                    TextSpan(text: 'g', style: AppTheme.labelSmall.copyWith(color: color, fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: AppTheme.bodySmall.copyWith(color: AppTheme.textOnDarkMuted, fontSize: 11)),
      ],
    );
  }
}
