import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../models/food_models.dart';
import '../../providers/meal_logging_provider.dart';

/// Correct a misidentified food or its portion. On save, PATCHes
/// /nutrition/meals/{id} with only what changed — the backend re-resolves
/// real nutrition through the same IFCT -> USDA -> Gemini chain every
/// other logging path uses (source_router.resolve_nutrition), so the
/// returned [MealSummary] reflects genuinely recomputed numbers, not a
/// relabeled version of the old ones.
Future<MealSummary?> showEditMealItemSheet(BuildContext context, MealSummary item) {
  return showModalBottomSheet<MealSummary?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.backgroundWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _EditMealItemSheet(item: item),
  );
}

class _EditMealItemSheet extends ConsumerStatefulWidget {
  final MealSummary item;
  const _EditMealItemSheet({required this.item});

  @override
  ConsumerState<_EditMealItemSheet> createState() => _EditMealItemSheetState();
}

class _EditMealItemSheetState extends ConsumerState<_EditMealItemSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _portionController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.foodName);
    _portionController = TextEditingController(text: widget.item.portionGrams?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _portionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final portionText = _portionController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a food name.');
      return;
    }
    final portion = portionText.isEmpty ? null : int.tryParse(portionText);
    if (portionText.isNotEmpty && (portion == null || portion <= 0)) {
      setState(() => _error = 'Enter a valid portion in grams.');
      return;
    }
    setState(() => _error = null);

    final nameChanged = name != widget.item.foodName;
    final portionChanged = portion != null && portion != widget.item.portionGrams;

    final updated = await ref.read(mealLoggingProvider.notifier).editMealItem(
          mealId: widget.item.id,
          foodName: nameChanged ? name : null,
          portionGrams: portionChanged ? portion : null,
        );

    if (!mounted) return;
    if (updated == null) {
      setState(() => _error = 'Could not update this item. Please try again.');
      return;
    }
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    final loggingState = ref.watch(mealLoggingProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit food', style: AppTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Correcting the name or portion re-checks the nutrition numbers.',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          Text('Food name', style: AppTheme.labelSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.backgroundSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          Text('Portion (grams)', style: AppTheme.labelSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _portionController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.backgroundSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              suffixText: 'g',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: AppTheme.bodySmall.copyWith(color: AppTheme.glucoseHyper)),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            text: 'Save',
            isLoading: loggingState.isLoading,
            onPressed: loggingState.isLoading ? null : _save,
          ),
        ],
      ),
    );
  }
}
