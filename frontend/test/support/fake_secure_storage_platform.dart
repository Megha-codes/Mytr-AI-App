/// An in-memory [FlutterSecureStoragePlatform] for tests.
///
/// `flutter_secure_storage` talks to the OS keychain/keystore through a
/// platform channel — under plain `flutter test` (no real device/emulator)
/// there's no platform implementation registered, so every real read/write/
/// delete call would throw `MissingPluginException`. AuthStorageService and
/// GoalsNotifier both happen to catch that (a corrupted-keystore fallback,
/// not a test convenience), which means tests that don't install this fake
/// would still run — but they'd never actually exercise a write/read/delete
/// at all, silently, which is exactly the wrong thing for a regression test
/// about data NOT persisting across users.
///
/// `FlutterSecureStoragePlatform.instance` is a single global static, and
/// every `FlutterSecureStorage()` instance in the app routes through it
/// regardless of which class constructed it — install this once in a
/// `setUp()` and both AuthStorageService's and GoalsNotifier's otherwise-
/// unrelated `FlutterSecureStorage()` instances (see the real cross-user
/// leak this was written for) share the exact same backing store, matching
/// how they actually behave on a real device.
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(_values);
  }

  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async {
    _values.clear();
  }
}
