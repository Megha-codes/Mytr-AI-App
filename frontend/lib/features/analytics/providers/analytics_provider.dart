import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../models/analytics_models.dart';

/// Mirrors backend GET /analytics/weekly (Phase-1 polish, part 2) — one
/// call backs the whole analytics screen (glucose TIR/GMI/trend, the
/// food-glucose correlation list, health trends, nutrition trends,
/// insights) instead of five separate fetches.
class AnalyticsNotifier extends AutoDisposeAsyncNotifier<WeeklyAnalytics> {
  @override
  Future<WeeklyAnalytics> build() async {
    final response = await ref.read(apiClientProvider).get('/analytics/weekly');
    return WeeklyAnalytics.fromJson(response.data as Map<String, dynamic>);
  }
}

final analyticsProvider =
    AsyncNotifierProvider.autoDispose<AnalyticsNotifier, WeeklyAnalytics>(
  AnalyticsNotifier.new,
);
