import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../glucose/providers/manual_glucose_provider.dart';
import '../../../core/widgets/primary_button.dart';

class ManualGlucoseEntrySheet extends ConsumerWidget {
  const ManualGlucoseEntrySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaving = ref.watch(manualGlucoseProvider).isSaving;

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
          const _GlucoseNumberInput(unit: 'mg/dL', minValue: 40, maxValue: 400),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: _ReadingTimeSelector(),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: PrimaryButton(
              text: 'Log entry',
              isLoading: isSaving,
              onPressed: () => _save(context, ref),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final value = ref.read(glucoseInputProvider);
    final time  = ref.read(readingTimeProvider);

    await ref.read(manualGlucoseProvider.notifier).save(
      valueMgdl: value,
      timestamp: time,
    );

    final error = ref.read(manualGlucoseProvider).error;
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (context.mounted) Navigator.pop(context);
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

class _GlucoseNumberInput extends ConsumerWidget {
  const _GlucoseNumberInput({
    required this.unit,
    required this.minValue,
    required this.maxValue,
  });

  final String unit;
  final int    minValue;
  final int    maxValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(glucoseInputProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          iconSize: 40,
          onPressed: value > minValue
              ? () => ref.read(glucoseInputProvider.notifier).update(value - 1)
              : null,
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
          onPressed: value < maxValue
              ? () => ref.read(glucoseInputProvider.notifier).update(value + 1)
              : null,
        ),
      ],
    );
  }
}

// ── Time picker ───────────────────────────────────────────────────────────────

class _ReadingTimeSelector extends ConsumerWidget {
  const _ReadingTimeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time  = ref.watch(readingTimeProvider);
    final isNow = DateTime.now().difference(time).abs().inMinutes < 1;

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
            if (picked != null && context.mounted) {
              final now = DateTime.now();
              ref.read(readingTimeProvider.notifier).update(DateTime(
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
