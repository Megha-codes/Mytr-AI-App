import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';

/// Mirrors backend GET /water/daily (Phase-1 polish, part 3) — totalMl is
/// null (not 0) when nothing has been logged today at all, same
/// null-vs-zero convention as every other daily metric in this app
/// (docs/health-data-setup.md).
class WaterState {
  final int? totalMl;
  final int goalMl;

  const WaterState({this.totalMl, this.goalMl = 2000});

  factory WaterState.fromJson(Map<String, dynamic> json) => WaterState(
        totalMl: (json['total_ml'] as num?)?.toInt(),
        goalMl: (json['goal_ml'] as num?)?.toInt() ?? 2000,
      );

  WaterState copyWith({int? totalMl, int? goalMl}) => WaterState(
        totalMl: totalMl ?? this.totalMl,
        goalMl: goalMl ?? this.goalMl,
      );
}

class WaterNotifier extends AutoDisposeAsyncNotifier<WaterState> {
  @override
  Future<WaterState> build() async {
    final response = await ref.read(apiClientProvider).get('/water/daily');
    return WaterState.fromJson(response.data as Map<String, dynamic>);
  }

  /// POST /water/log already returns the day's new running total, so this
  /// updates state directly from the response instead of a second
  /// round-trip to GET /water/daily just to redisplay what the log call
  /// already told us.
  Future<void> logWater(int amountMl) async {
    final response = await ref.read(apiClientProvider).post(
      '/water/log',
      data: {'amount_ml': amountMl},
    );
    final total = (response.data as Map<String, dynamic>)['total_ml_today'] as num;
    state = AsyncData((state.valueOrNull ?? const WaterState()).copyWith(totalMl: total.toInt()));
  }
}

final waterProvider =
    AsyncNotifierProvider.autoDispose<WaterNotifier, WaterState>(WaterNotifier.new);
