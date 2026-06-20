import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../models/models.dart';
import '../../../../core/icons/lucide_icons.dart';

class CameraOverlay extends StatefulWidget {
  const CameraOverlay({super.key});

  @override
  State<CameraOverlay> createState() => _CameraOverlayState();
}

class _CameraOverlayState extends State<CameraOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Corners
        Positioned(left: 40, top: 100, child: _Corner(angle: 0)),
        Positioned(right: 40, top: 100, child: _Corner(angle: 90)),
        Positioned(left: 40, bottom: 100, child: _Corner(angle: 270)),
        Positioned(right: 40, bottom: 100, child: _Corner(angle: 180)),

        // Scan Line
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Positioned(
              left: 50,
              right: 50,
              top: 100 + (300 * _controller.value),
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(color: AppTheme.brandGreen.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2),
                  ],
                  gradient: LinearGradient(
                    colors: [Colors.transparent, AppTheme.brandGreen, Colors.transparent],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Corner extends StatelessWidget {
  final double angle;
  const _Corner({required this.angle});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle * 3.14159 / 180,
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: AppTheme.brandGreen, width: 4),
            top: BorderSide(color: AppTheme.brandGreen, width: 4),
          ),
        ),
      ),
    );
  }
}

class DetectionBanner extends StatelessWidget {
  final LoggedMeal meal;
  final String confidence;

  const DetectionBanner({super.key, required this.meal, required this.confidence});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppTheme.accentCyan,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(meal.name, style: AppTheme.titleMedium.copyWith(color: Colors.white, fontSize: 24))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                child: Text('$confidence conf.', style: AppTheme.labelSmall.copyWith(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMacro('${meal.calories}', 'Cal'),
              _buildMacro('${meal.carbsG}g', 'Carbs'),
              _buildMacro('${meal.proteinG}g', 'Prot'),
              _buildMacro('${meal.glycaemicLoad}', 'GL'),
            ],
          ),
          if (meal.glycaemicLoad > 10) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(LucideIcons.alertTriangle, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Moderate glucose rise expected in ~${meal.estimatedRiseMinutes} mins',
                      style: AppTheme.bodySmall.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              child: Text('Not right?', style: AppTheme.labelSmall.copyWith(color: Colors.white.withValues(alpha: 0.7))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacro(String value, String label) {
    return Column(
      children: [
        Text(value, style: AppTheme.titleLarge.copyWith(color: Colors.white)),
        Text(label, style: AppTheme.labelSmall.copyWith(color: Colors.white.withValues(alpha: 0.6))),
      ],
    );
  }
}

class BolusRecommendationCard extends StatelessWidget {
  final double dose;
  final double adjustment;
  final List<String> drivers;
  final double confidence;
  final bool showDoctorFlag;
  final VoidCallback onConfirm;

  const BolusRecommendationCard({
    super.key,
    required this.dose,
    required this.adjustment,
    required this.drivers,
    required this.confidence,
    required this.showDoctorFlag,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BOLUS RECOMMENDATION', style: AppTheme.labelSmall),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(dose.toStringAsFixed(1), style: AppTheme.displayLarge.copyWith(fontSize: 64)),
                  const SizedBox(width: 8),
                  Text('units', style: AppTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    adjustment < 0 ? LucideIcons.arrowDown : LucideIcons.arrowUp,
                    size: 16,
                    color: adjustment < 0 ? AppTheme.brandGreen : AppTheme.accentOrange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${adjustment.abs().toInt()}% lifestyle adjustment',
                    style: AppTheme.bodySmall.copyWith(
                      color: adjustment < 0 ? AppTheme.brandGreen : AppTheme.accentOrange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppTheme.brandGreenLight, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: drivers.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.check, size: 14, color: AppTheme.brandGreenDark),
                        const SizedBox(width: 8),
                        Text(d, style: AppTheme.bodySmall.copyWith(color: AppTheme.brandGreenDark)),
                      ],
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 24),
              if (showDoctorFlag) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber)),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.stethoscope, color: Colors.amber, size: 18),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Low confidence — consult your doctor before dosing', style: AppTheme.bodySmall.copyWith(color: Colors.amber.shade900))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final active = index < (confidence * 5).toInt();
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: active ? AppTheme.brandGreen : AppTheme.borderLight),
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text(
                _getConfidenceLabel(),
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brandGreen,
                        foregroundColor: AppTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text('Confirm dose'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(LucideIcons.share2),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: AppTheme.backgroundCream,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getConfidenceLabel() {
    if (confidence > 0.8) return 'High Confidence';
    if (confidence > 0.5) return 'Moderate Confidence';
    return 'Low Confidence';
  }
}

class NutritionSummaryCard extends StatelessWidget {
  final LoggedMeal meal;
  final VoidCallback onLog;

  const NutritionSummaryCard({super.key, required this.meal, required this.onLog});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              _MacroChip(label: '${meal.carbsG}g Carbs', color: AppTheme.accentCyan),
              const SizedBox(width: 8),
              _MacroChip(label: '${meal.proteinG}g Prot', color: AppTheme.brandGreen),
              const SizedBox(width: 8),
              _MacroChip(label: '${meal.fatG}g Fat', color: AppTheme.accentOrange),
            ],
          ),
          const SizedBox(height: 24),
          Text('+ ${meal.calories} kcal', style: AppTheme.displayLarge.copyWith(color: AppTheme.textPrimary)),
          Text('added to your daily log', style: AppTheme.bodySmall),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onLog,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandGreen,
                foregroundColor: AppTheme.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('Add to log'),
            ),
          ),
          TextButton(onPressed: () {}, child: Text('Not eating this', style: TextStyle(color: AppTheme.textSecondary))),
        ],
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MacroChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: AppTheme.labelSmall.copyWith(color: color)),
    );
  }
}

class MealHistoryList extends StatelessWidget {
  final List<LoggedMeal> meals;

  const MealHistoryList({super.key, required this.meals});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("TODAY'S MEALS", style: AppTheme.labelSmall),
        const SizedBox(height: 16),
        ...meals.map((meal) => _MealRow(meal: meal)),
      ],
    );
  }
}

class _MealRow extends StatelessWidget {
  final LoggedMeal meal;
  const _MealRow({required this.meal});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: AppTheme.backgroundCream, borderRadius: BorderRadius.circular(12)),
              child: const Center(child: Text('🍽️', style: TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meal.name, style: AppTheme.titleMedium),
                  Text('${meal.timestamp.hour}:${meal.timestamp.minute.toString().padLeft(2, '0')}', style: AppTheme.bodySmall),
                ],
              ),
            ),
            Text('${meal.calories} kcal', style: AppTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
