import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/config.dart';
import '../../home/models/models.dart';

class AchievementState {
  final List<Achievement> unlockedAchievements;
  final List<Achievement> allAchievements;
  final Achievement? newlyUnlocked; // For celebration trigger

  AchievementState({
    required this.unlockedAchievements,
    required this.allAchievements,
    this.newlyUnlocked,
  });

  AchievementState copyWith({
    List<Achievement>? unlockedAchievements,
    List<Achievement>? allAchievements,
    Achievement? newlyUnlocked,
  }) {
    return AchievementState(
      unlockedAchievements: unlockedAchievements ?? this.unlockedAchievements,
      allAchievements: allAchievements ?? this.allAchievements,
      newlyUnlocked: newlyUnlocked,
    );
  }
}

class AchievementsNotifier extends AutoDisposeAsyncNotifier<AchievementState> {
  WebSocketChannel? _channel;

  @override
  FutureOr<AchievementState> build() async {
    _initWebSocket();
    return _fetchAchievements();
  }

  Future<AchievementState> _fetchAchievements() async {
    final response = await ref.read(apiClientProvider).get('/achievements');
    final List all = (response.data as List);
    final list = all.map((a) => Achievement(
      id: a['id'],
      title: a['title'],
      icon: a['icon'],
      category: a['category'],
      isUnlocked: a['is_unlocked'] ?? false,
    )).toList();
    
    return AchievementState(
      allAchievements: list,
      unlockedAchievements: list.where((a) => a.isUnlocked).toList(),
    );
  }

  void _initWebSocket() {
    _channel = WebSocketChannel.connect(
      Uri.parse('${AppConfig.wsBaseUrl}/ws/notifications/current_user'),
    );

    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      if (data['type'] == 'ACHIEVEMENT_UNLOCKED') {
        final a = data['payload'];
        final achievement = Achievement(
          id: a['id'],
          title: a['title'],
          icon: a['icon'],
          category: a['category'],
          isUnlocked: true,
        );
        if (state.hasValue) {
          state = AsyncData(state.value!.copyWith(
            newlyUnlocked: achievement,
            unlockedAchievements: [achievement, ...state.value!.unlockedAchievements],
          ));
        }
      }
    });
    
    ref.onDispose(() => _channel?.sink.close());
  }

  void clearCelebration() {
    if (state.hasValue) {
      state = AsyncData(state.value!.copyWith(newlyUnlocked: null));
    }
  }
}

final achievementsProvider = AsyncNotifierProvider.autoDispose<AchievementsNotifier, AchievementState>(() {
  return AchievementsNotifier();
});
