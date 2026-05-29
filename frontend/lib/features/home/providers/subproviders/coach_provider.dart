import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../models/models.dart';

class CoachNotifier extends AutoDisposeAsyncNotifier<CoachState> {
  @override
  FutureOr<CoachState> build() => _fetchCoach();

  Future<CoachState> _fetchCoach() async {
    final response = await ref.read(apiClientProvider).get('/coach/insights');
    return CoachState.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchCoach());
  }
}

final coachProvider =
    AsyncNotifierProvider.autoDispose<CoachNotifier, CoachState>(() {
      return CoachNotifier();
    });
