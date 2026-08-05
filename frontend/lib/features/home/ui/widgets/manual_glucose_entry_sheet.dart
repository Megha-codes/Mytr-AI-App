import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../../../core/widgets/primary_button.dart';

/// Bottom sheet for a manual (fingerstick/Accu-Chek) glucose entry.
/// Posts through [ManualGlucoseService], which invalidates [dashboardProvider]
/// on success so the glucose screen and card refresh with the new reading —
/// the same store POST /glucose/manual already publishes into the fanout hub
/// for anyone with a live /ws/app/stream connection.
class ManualGlucoseEntrySheet extends ConsumerStatefulWidget {
  const ManualGlucoseEntrySheet({super.key});

  @override
  ConsumerState<ManualGlucoseEntrySheet> createState() => _ManualGlucoseEntrySheetState();
}

class _ManualGlucoseEntrySheetState extends ConsumerState<ManualGlucoseEntrySheet> {
  static const int _minValue = 40;
  static const int _maxValue = 400;

  int _value = 100;
  DateTime _time = DateTime.now();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final isNow = DateTime.now().difference(_time).abs().inMinutes < 1;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 8),
          Text(
            'Log glucose reading',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          _GlucoseNumberInput(
            value: _value,
            unit: 'mg/dL',
            minValue: _minValue,
            maxValue: _maxValue,
            onChanged: (v) => setState(() => _value = v),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _ReadingTimeSelector(
              time: _time,
              isNow: isNow,
              onPick: (picked) => setState(() => _time = picked),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: PrimaryButton(
              text: 'Log entry',
              isLoading: _isSaving,
              onPressed: _isSaving ? null : () => _save(context),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    setState(() => _isSaving = true);
    try {
      await ref.read(manualGlucoseProvider).logReading(
            _value.toDouble(),
            timestamp: _time,
          );
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      final message = e is DioException
          ? (e.response?.data?['detail']?.toString() ?? 'Failed to save reading. Please try again.')
          : 'Failed to save reading. Please try again.';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ── Sheet handle ─────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ── Large number stepper ──────────────────────────────────────────────────────

class _GlucoseNumberInput extends StatelessWidget {
  const _GlucoseNumberInput({
    required this.value,
    required this.unit,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
  });

  final int value;
  final String unit;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          iconSize: 40,
          onPressed: value > minValue ? () => onChanged(value - 1) : null,
        ),
        const SizedBox(width: 24),
        Column(
          children: [
            Text(
              '$value',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(unit, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(width: 24),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          iconSize: 40,
          onPressed: value < maxValue ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

// ── Time picker ───────────────────────────────────────────────────────────────

class _ReadingTimeSelector extends StatelessWidget {
  const _ReadingTimeSelector({
    required this.time,
    required this.isNow,
    required this.onPick,
  });

  final DateTime time;
  final bool isNow;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Reading time'),
        TextButton.icon(
          icon: const Icon(Icons.access_time, size: 16),
          label: Text(isNow ? 'Now' : _fmt(time)),
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(time),
            );
            if (picked != null) {
              final now = DateTime.now();
              onPick(DateTime(
                now.year, now.month, now.day,
                picked.hour, picked.minute,
              ));
            }
          },
        ),
      ],
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
