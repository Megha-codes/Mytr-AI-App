import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../models/paired_device.dart';

class DeviceListNotifier extends AutoDisposeAsyncNotifier<List<PairedDevice>> {
  @override
  Future<List<PairedDevice>> build() => _fetch();

  Future<List<PairedDevice>> _fetch() async {
    final response = await ref.read(apiClientProvider).get('/devices');
    final raw = response.data as List<dynamic>;
    return raw.map((d) => PairedDevice.fromJson(d as Map<String, dynamic>)).toList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Returns null on success, or a user-facing error message on failure.
  Future<String?> rename(String deviceId, String name) async {
    try {
      await ref.read(apiClientProvider).patch('/devices/$deviceId', data: {'name': name});
      await refresh();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? 'Failed to rename device.';
    }
  }

  /// Returns null on success, or a user-facing error message on failure.
  Future<String?> unpair(String deviceId) async {
    try {
      await ref.read(apiClientProvider).delete('/devices/$deviceId');
      await refresh();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? 'Failed to unpair device.';
    }
  }
}

final deviceListProvider =
    AsyncNotifierProvider.autoDispose<DeviceListNotifier, List<PairedDevice>>(() {
  return DeviceListNotifier();
});
