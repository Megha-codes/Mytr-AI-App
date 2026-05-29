import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProfileNotifier extends AutoDisposeNotifier<void> {
  @override
  void build() {}

  Future<void> uploadAvatar(File image) async {
    // Mock upload
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<String> generateShareLink() async {
    // Mock generation
    await Future.delayed(const Duration(seconds: 1));
    return 'https://mytr.ai/share/alex123';
  }
}

final profileProvider = NotifierProvider.autoDispose<ProfileNotifier, void>(() {
  return ProfileNotifier();
});
