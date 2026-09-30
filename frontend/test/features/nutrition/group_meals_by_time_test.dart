import 'package:flutter_test/flutter_test.dart';
import 'package:metasync_app/features/nutrition/models/food_models.dart';
import 'package:metasync_app/features/nutrition/providers/meals_list_provider.dart';

/// meal_logs has no grouping column — every item logged from one photo
/// capture shares an identical meal_time (see meal_recognition_provider.dart),
/// and that's the only join key groupMealsByTime has to work with.
void main() {
  MealSummary item(String id, DateTime mealTime, String name, {int? calories}) {
    return MealSummary(id: id, mealTime: mealTime, foodName: name, calories: calories);
  }

  test('groups items sharing the exact same meal_time into one meal', () {
    final t = DateTime.utc(2026, 1, 1, 12, 0);
    final meals = [
      item('a', t, 'Rice', calories: 200),
      item('b', t, 'Dal', calories: 150),
      item('c', DateTime.utc(2026, 1, 1, 18, 0), 'Roti', calories: 100),
    ];

    final groups = groupMealsByTime(meals);

    expect(groups, hasLength(2));
    final lunchGroup = groups.firstWhere((g) => g.mealTime == t);
    expect(lunchGroup.items, hasLength(2));
    expect(lunchGroup.totalCalories, 350);
  });

  test('sorts groups newest first', () {
    final earlier = DateTime.utc(2026, 1, 1, 8, 0);
    final later = DateTime.utc(2026, 1, 1, 20, 0);
    final meals = [item('a', earlier, 'Breakfast'), item('b', later, 'Dinner')];

    final groups = groupMealsByTime(meals);

    expect(groups.first.mealTime, later);
    expect(groups.last.mealTime, earlier);
  });

  test('a single-item meal groups to a list of one', () {
    final groups = groupMealsByTime([item('a', DateTime.utc(2026, 1, 1), 'Banana')]);
    expect(groups, hasLength(1));
    expect(groups.first.items, hasLength(1));
  });

  test('representativeMealId is the first item in the group', () {
    final t = DateTime.utc(2026, 1, 1);
    final groups = groupMealsByTime([item('x', t, 'A'), item('y', t, 'B')]);
    expect(groups.first.representativeMealId, groups.first.items.first.id);
  });

  test('label joins every item name in the group', () {
    final t = DateTime.utc(2026, 1, 1);
    final groups = groupMealsByTime([item('a', t, 'Rice'), item('b', t, 'Dal')]);
    expect(groups.first.label, 'Rice, Dal');
  });
}
