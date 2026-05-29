import 'cgm_arc_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../glucose/models/glucose_reading.dart';
import '../../glucose/services/glucose_stream_service.dart';
import '../../../core/app_colors.dart';
import '../../../core/widgets/meta_sync_card.dart';

class LiveGlucoseCard extends ConsumerWidget {
  const LiveGlucoseCard({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glucoseAsync = ref.watch(glucoseStreamProvider(userId));

    return glucoseAsync.when(
      data: (reading) => _GlucoseCardContent(reading: reading),
      loading: () => const _GlucoseCardShimmer(),
      error: (_, _) => const _GlucoseCardError(),
    );
  }
}



class _GlucoseCardContent extends StatelessWidget {
  const _GlucoseCardContent({required this.reading});

  final GlucoseReading reading;

  @override
  Widget build(BuildContext context) {
    final rangeStatus = reading.getRangeStatus();
    final valueColor = _glucoseColor(rangeStatus);

    // Max bounds for the gauge, e.g. 400 mg/dL max visual bound
    // 127 mg/dL / 400 = 31% fill.
    const maxMgdl = 400.0;

    return MetaSyncCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE GLUCOSE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
              reading.isContinuous
                  ? const _LiveBadge()
                  : _LastReadingBadge(timestamp: reading.timestamp),
            ],
          ),
          const SizedBox(height: 24),
          
          // Custom Arc Gauge
          SizedBox(
            height: 200,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: CustomPaint(
                    painter: CgmArcPainter(
                      valueMgdl: reading.valueMgdl.toDouble(),
                      maxMgdl: maxMgdl,
                      valueColor: valueColor,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${reading.valueMgdl}',
                          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            color: valueColor,
                          ),
                        ),
                        if (reading.supportsTrend) ...[
                          const SizedBox(width: 4),
                          Text(
                            reading.trendArrow!,
                            style: TextStyle(fontSize: 28, color: valueColor),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'mg/dL',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          _RangeStatusPill(status: rangeStatus),
          const SizedBox(height: 32),

          // Quick Log Buttons (Indigo / Orange)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.water_drop, color: Colors.white, size: 18),
                  label: const Text('Log Bolus', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricIndigo,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.restaurant, color: Colors.white, size: 18),
                  label: const Text('Log Meal', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.vividOrange,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _glucoseColor(RangeStatus status) => switch (status) {
    RangeStatus.inRange => AppColors.glucoseGreen,
    RangeStatus.high => AppColors.glucoseOrange,
    RangeStatus.low => AppColors.glucoseRed,
    RangeStatus.hypo => AppColors.glucoseDarkRed,
    RangeStatus.hyper => AppColors.glucoseDarkOrange,
  };
}

// ── Badge widgets ────────────────────────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.glucoseGreen,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'LIVE',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.glucoseGreen),
        ),
      ],
    );
  }
}

class _LastReadingBadge extends StatelessWidget {
  const _LastReadingBadge({required this.timestamp});

  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final minutes = DateTime.now().difference(timestamp).inMinutes;
    return Text(
      'Last: $minutes min ago',
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: Colors.grey),
    );
  }
}

// ── Chart stubs ──────────────────────────────────────────────────────────────

// ── Range pill ───────────────────────────────────────────────────────────────

class _RangeStatusPill extends StatelessWidget {
  const _RangeStatusPill({required this.status});

  final RangeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      RangeStatus.inRange => ('In Range', AppColors.glucoseGreen),
      RangeStatus.high => ('High', AppColors.glucoseOrange),
      RangeStatus.hyper => ('Very High', AppColors.glucoseDarkOrange),
      RangeStatus.low => ('Low', AppColors.glucoseRed),
      RangeStatus.hypo => ('Hypo', AppColors.glucoseDarkRed),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ── Error / loading states ───────────────────────────────────────────────────

class _GlucoseCardShimmer extends StatelessWidget {
  const _GlucoseCardShimmer();

  @override
  Widget build(BuildContext context) {
    return MetaSyncCard(
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _GlucoseCardError extends StatelessWidget {
  const _GlucoseCardError();

  @override
  Widget build(BuildContext context) {
    return MetaSyncCard(
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            'CGM unavailable — reconnecting...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
