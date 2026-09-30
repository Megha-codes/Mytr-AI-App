import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/dark_header.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../models/food_models.dart';
import '../../providers/meal_glucose_response_provider.dart';
import '../../providers/meals_list_provider.dart';
import '../widgets/edit_meal_item_sheet.dart';
import '../widgets/macro_rings_card.dart';
import '../widgets/meal_glucose_response_card.dart';
import '../widgets/meal_item_row.dart';
import '../widgets/nutrition_flags_row.dart';

/// One logged meal — the per-item breakdown, macro rings, real glucose
/// response (or its empty state), and neutral descriptive flags. Reached
/// by tapping a row in the "Today's meals" list.
class MealDetailScreen extends ConsumerStatefulWidget {
  final GroupedMeal meal;

  const MealDetailScreen({super.key, required this.meal});

  @override
  ConsumerState<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends ConsumerState<MealDetailScreen> {
  late List<MealSummary> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.meal.items;
  }

  Future<void> _editItem(MealSummary item) async {
    final updated = await showEditMealItemSheet(context, item);
    if (updated == null) return;
    setState(() {
      _items = [for (final i in _items) if (i.id == updated.id) updated else i];
    });
    // The "Today's meals" list caches its own copy — make sure it picks up
    // the correction next time it's shown instead of quietly going stale.
    ref.invalidate(todaysMealsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final totalCalories = _items.fold(0, (sum, i) => sum + (i.calories ?? 0));
    final totalCarbs = _items.fold(0.0, (sum, i) => sum + (i.carbsG ?? 0));
    final totalProtein = _items.fold(0.0, (sum, i) => sum + (i.proteinG ?? 0));
    final totalFat = _items.fold(0.0, (sum, i) => sum + (i.fatG ?? 0));
    final totalFiber = _items.fold(0.0, (sum, i) => sum + (i.fiberG ?? 0));
    final totalGL = _items.fold(0.0, (sum, i) => sum + (i.glycaemicLoad ?? 0));

    final glucoseAsync = ref.watch(mealGlucoseResponseProvider(_items.first.id));

    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: SingleChildScrollView(
        child: Column(
          children: [
            DarkHeader(
              title: 'Meal Details',
              eyebrow: _formatDateTime(widget.meal.mealTime),
              eyebrowColor: AppTheme.textOnDarkMuted,
              trailing: IconButton(
                icon: const Icon(LucideIcons.arrowLeft, color: AppTheme.textOnDark),
                onPressed: () => context.pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  glucoseAsync.when(
                    data: (response) => MealGlucoseResponseCard(response: response, mealTime: widget.meal.mealTime),
                    loading: () => const CardShimmer(height: 260),
                    error: (e, _) => const SizedBox.shrink(), // glucose section is a bonus, not core — fail quiet
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundDark,
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('YOUR MEAL', style: AppTheme.labelSmall.copyWith(color: AppTheme.textOnDarkMuted)),
                          for (final item in _items)
                            MealItemRow(
                              name: item.foodName,
                              portionLabel: item.portionGrams != null ? '${item.portionGrams}g' : '',
                              nutritionVerified: item.nutritionVerified ?? true,
                              onTap: () => _editItem(item),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  MacroRingsCard(
                    calories: totalCalories,
                    proteinG: totalProtein,
                    fatG: totalFat,
                    carbsG: totalCarbs,
                    fiberG: totalFiber,
                  ),
                  const SizedBox(height: 16),
                  NutritionFlagsRow(glycaemicLoad: totalGL, fiberG: totalFiber),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime t) {
    final local = t.toLocal();
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${weekdays[local.weekday - 1]}, ${months[local.month - 1]} ${local.day} · $hour:$minute $period';
  }
}
