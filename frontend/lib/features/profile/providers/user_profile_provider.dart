import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../home/models/models.dart';

class UserProfileNotifier extends AutoDisposeAsyncNotifier<UserProfile> {
  @override
  FutureOr<UserProfile> build() => _fetchProfile();

  Future<UserProfile> _fetchProfile() async {
    final response = await ref.read(apiClientProvider).get('/user/profile');
    return UserProfile.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> updateName(String name) async {
    if (!state.hasValue) return;
    // Optimistic local update while we have no update endpoint yet
    state = AsyncData(UserProfile(
      displayName: name,
      avatarImageUrl: state.value!.avatarImageUrl,
      userType: state.value!.userType,
      currentLevel: state.value!.currentLevel,
      levelTitle: state.value!.levelTitle,
      currentXP: state.value!.currentXP,
      xpToNextLevel: state.value!.xpToNextLevel,
      startingWeight: state.value!.startingWeight,
      weightGoal: state.value!.weightGoal,
      primaryGoal: state.value!.primaryGoal,
      recentAchievements: state.value!.recentAchievements,
    ));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchProfile);
  }
}

final userProfileProvider =
    AsyncNotifierProvider.autoDispose<UserProfileNotifier, UserProfile>(
  UserProfileNotifier.new,
);
