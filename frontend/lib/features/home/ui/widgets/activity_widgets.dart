import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/stat_widgets.dart';
import '../../models/models.dart';

class CircularProgressRing extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final String label;

  const CircularProgressRing({super.key, required this.progress, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(80, 80),
            painter: _RingPainter(progress: progress),
          ),
          Text(
            label,
            style: AppTheme.labelLarge.copyWith(fontSize: 14, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;

  _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = 8.0;

    final bgPaint = Paint()
      ..color = AppTheme.brandGreenDark.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final progressPaint = Paint()
      ..color = AppTheme.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius - strokeWidth / 2, bgPaint);

    final angle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -math.pi / 2,
      angle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class SleepStageBar extends StatelessWidget {
  final List<SleepStage> stages;

  const SleepStageBar({super.key, required this.stages});

  @override
  Widget build(BuildContext context) {
    final totalHours = stages.fold(0.0, (sum, item) => sum + item.hours);
    
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 24,
            child: Row(
              children: stages.map((SleepStage stage) {
                final weight = (stage.hours / totalHours * 100).toInt();
                return Expanded(
                  flex: weight,
                  child: Container(color: _getStageColor(stage.type)),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: stages.map((SleepStage stage) => _buildStageStat(stage)).toList(),
        ),
      ],
    );
  }

  Color _getStageColor(SleepStageType type) {
    return switch (type) {
      SleepStageType.awake => AppTheme.backgroundSurface,
      SleepStageType.light => AppTheme.accentCyan.withValues(alpha: 0.3),
      SleepStageType.deep  => AppTheme.brandGreen,
      SleepStageType.rem   => AppTheme.accentCyan,
    };
  }

  Widget _buildStageStat(SleepStage stage) {
    return Column(
      children: [
        Text('${stage.hours}h', style: AppTheme.labelLarge.copyWith(color: _getStageColor(stage.type))),
        Text(stage.type.name.toUpperCase(), style: AppTheme.labelSmall.copyWith(fontSize: 8)),
      ],
    );
  }
}

class StepsStrip extends StatelessWidget {
  /// Null means no Health Connect/HealthKit sample for today at all — not
  /// a genuine 0. Steps is phone-only (no wearable needed), so this is
  /// specifically a "permission not granted / not synced yet" state.
  final int? steps;
  final int goal;
  final double percent;

  /// Only used when [steps] is null.
  final VoidCallback? onConnect;

  const StepsStrip({
    super.key,
    required this.steps,
    required this.goal,
    required this.percent,
    this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.brandGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('STEPS TODAY', style: AppTheme.labelSmall.copyWith(color: AppTheme.brandGreenDark.withValues(alpha: 0.6))),
                const SizedBox(height: 4),
                if (steps != null) ...[
                  Text('$steps', style: AppTheme.displayLarge.copyWith(color: AppTheme.textPrimary, fontSize: 36)),
                  Text('of $goal goal', style: AppTheme.bodySmall.copyWith(color: AppTheme.brandGreenDark.withValues(alpha: 0.6))),
                ] else ...[
                  Text('No data', style: AppTheme.displayMedium.copyWith(color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  const MetricHintBox(
                    text: 'Grant Health permission to see steps.',
                    color: AppTheme.brandGreenDark,
                  ),
                ],
              ],
            ),
          ),
          if (steps != null)
            CircularProgressRing(
              progress: percent,
              label: '${(percent * 100).toInt()}%',
            ),
        ],
      ),
    );

    if (steps != null || onConnect == null) return content;
    return InkWell(
      onTap: onConnect,
      borderRadius: BorderRadius.circular(16),
      child: content,
    );
  }
}
