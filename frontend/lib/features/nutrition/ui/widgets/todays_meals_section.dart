import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../core/widgets/state_feedback_widgets.dart';
import '../../providers/meals_list_provider.dart';

/// Entry point into the meal-detail screen — today's logged meals, newest
/// first, each row tappable. Nothing was tappable into a meal's detail
/// before this existed at all.
class TodaysMealsSection extends ConsumerWidget {
  const TodaysMealsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mealsAsync = ref.watch(todaysMealsProvider);

    return mealsAsync.when(
      data: (groups) {
        if (groups.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("TODAY'S MEALS", style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            for (final group in groups) ...[
              _MealRow(group: group),
              const Divider(height: 1),
            ],
          ],
        );
      },
      loading: () => const CardShimmer(height: 120),
      error: (e, _) => InlineErrorCard(
        message: 'Could not load today\'s meals',
        onRetry: () => ref.invalidate(todaysMealsProvider),
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  final GroupedMeal group;
  const _MealRow({required this.group});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/meals/detail', extra: group),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.label,
                    style: AppTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(_timeLabel(group.mealTime), style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('${group.totalCalories} kcal', style: AppTheme.labelLarge.copyWith(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  static String _timeLabel(DateTime t) {
    final local = t.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
