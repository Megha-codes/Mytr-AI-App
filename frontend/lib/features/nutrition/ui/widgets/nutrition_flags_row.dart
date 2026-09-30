import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Neutral, descriptive flags derived from real numbers — "high glycaemic
/// load", "low fiber". Never a verdict: no "avoid this", no "you've
/// exceeded a limit", no personalized directive. Describes the data;
/// doesn't prescribe. If nothing crosses a threshold, this renders
/// nothing at all — silence, not a forced "everything's fine" message.
class NutritionFlagsRow extends StatelessWidget {
  final double glycaemicLoad;
  final double fiberG;

  const NutritionFlagsRow({super.key, required this.glycaemicLoad, required this.fiberG});

  @override
  Widget build(BuildContext context) {
    final flags = _computeFlags(glycaemicLoad, fiberG);
    if (flags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: flags.map((f) => _FlagChip(text: f)).toList(),
    );
  }

  // Standard clinical GL bands (low <=10, medium 11-19, high >=20) — medium
  // isn't flagged at all, only the two ends worth noting factually.
  static List<String> _computeFlags(double gl, double fiberG) {
    final flags = <String>[];
    if (gl >= 20) {
      flags.add('High glycaemic load');
    } else if (gl > 0 && gl <= 10) {
      flags.add('Low glycaemic load');
    }
    if (fiberG < 3) {
      flags.add('Low fiber');
    } else if (fiberG >= 8) {
      flags.add('High fiber');
    }
    return flags;
  }
}

class _FlagChip extends StatelessWidget {
  final String text;

  const _FlagChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSurface,
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Text(text, style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary, letterSpacing: 0)),
    );
  }
}
