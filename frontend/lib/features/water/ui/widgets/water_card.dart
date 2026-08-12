import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../providers/water_provider.dart';

const _quickAddMl = 250;

/// Today's water total vs goal, plus the quick-log control (Phase-1
/// polish, part 3). Unlike every other card on this screen, water has no
/// "needs a wearable" / "needs permission" gate at all — logging *is* the
/// fix, so the empty state here is just an invitation to add the first
/// glass, not a docs/health-data-setup.md-style explanation.
class WaterCard extends ConsumerWidget {
  const WaterCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waterAsync = ref.watch(waterProvider);

    return AppCard(
      child: waterAsync.when(
        data: (water) => _buildContent(context, ref, water),
        loading: () => const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => SizedBox(
          height: 60,
          child: Center(
            child: TextButton(
              onPressed: () => ref.invalidate(waterProvider),
              child: const Text('Retry'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, WaterState water) {
    final total = water.totalMl ?? 0;
    final percent = water.goalMl == 0 ? 0.0 : (total / water.goalMl).clamp(0, 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Water', style: AppTheme.titleLarge),
            Text(
              water.totalMl != null ? '${water.totalMl} / ${water.goalMl} ml' : 'No water logged yet',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 10,
            backgroundColor: AppTheme.borderLight,
            valueColor: const AlwaysStoppedAnimation(AppTheme.accentCyan),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _log(context, ref, _quickAddMl),
                icon: const Icon(LucideIcons.droplet, size: 16),
                label: const Text('+250ml'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _showCustomAmountSheet(context, ref),
                child: const Text('Custom'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _log(BuildContext context, WidgetRef ref, int amountMl) async {
    try {
      await ref.read(waterProvider.notifier).logWater(amountMl);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not log water — try again.')),
        );
      }
    }
  }

  void _showCustomAmountSheet(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add water', style: AppTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Amount',
                suffixText: 'ml',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final amount = int.tryParse(controller.text.trim());
                  Navigator.of(sheetContext).pop();
                  if (amount != null && amount > 0) {
                    _log(context, ref, amount);
                  }
                },
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
