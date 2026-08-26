/// Regression test for a critical privacy bug: user A logs in, logs out,
/// then user B logs in on the same device (no app restart in between) —
/// and used to still see user A's goals, chat history, insulin dose
/// recommendation, and paired-device list. See auth_provider.dart's
/// _clearAllUserState() for the fix and its full writeup.
///
/// Exercises the REAL production notifiers (AuthNotifier, GoalsNotifier,
/// ChatNotifier, InferenceNotifier, DeviceListNotifier) through a
/// ProviderContainer, with only the network (FakeApiClient) and the secure
/// storage platform channel (FakeSecureStoragePlatform) faked — the same
/// level a real device fakes nothing at. If a future change reintroduces a
/// non-autoDispose or un-invalidated user-scoped provider, this is meant to
/// be the test that catches it — see AuthNotifier._clearAllUserState's own
/// doc comment for the rule new providers need to follow.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metasync_app/core/api/api_client.dart';
import 'package:metasync_app/features/auth/providers/auth_provider.dart';
import 'package:metasync_app/features/chat/providers/chat_provider.dart';
import 'package:metasync_app/features/devices/providers/device_list_provider.dart';
import 'package:metasync_app/features/home/models/models.dart';
import 'package:metasync_app/features/home/providers/subproviders/inference_provider.dart';
import 'package:metasync_app/features/profile/providers/goals_provider.dart';

import '../../support/fake_api_client.dart';
import '../../support/fake_secure_storage_platform.dart';

void main() {
  setUp(() {
    // One fresh in-memory "keychain" per test — see the fake's own doc
    // comment for why this is necessary at all under `flutter test`.
    FlutterSecureStoragePlatform.instance = FakeSecureStoragePlatform();
  });

  test(
    "logging out and a different user logging in leaves none of the first "
    'user\'s goals, chat history, insulin recommendation, or paired '
    'devices visible',
    () async {
      final fakeApi = FakeApiClient()..respondingAs = 'a';
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(fakeApi)],
      );
      addTearDown(container.dispose);

      // Let AuthNotifier's initial build() (reads storage, finds nothing)
      // settle before driving it, same as the app does at cold start.
      await container.read(authProvider.future);

      // ── User A logs in and accumulates real, personal data ──────────────
      await container.read(authProvider.notifier).login('a@example.com', 'pw');

      // Let goalsProvider's own initial build() (an async storage read)
      // settle before mutating it — otherwise that pending build() can
      // resolve AFTER save() and clobber it right back to the stored
      // (empty) default, a race that's specific to firing these calls
      // back-to-back in a test rather than across real user interaction.
      await container.read(goalsProvider.future);
      await container.read(goalsProvider.notifier).save(
            const Goals(weightGoalKg: 82, dailyStepGoal: 5000, dailyCalorieGoal: 1800),
          );
      await container.read(chatProvider.notifier).sendMessage('What was my glucose today?');
      await container.read(inferenceProvider.notifier).computeRecommendation(
            LoggedMeal(
              id: 'meal-a',
              name: 'Dal + rice',
              timestamp: DateTime(2026, 1, 1),
              calories: 540,
              carbsG: 72,
              proteinG: 18,
              fatG: 12,
            ),
          );
      await container.read(deviceListProvider.future);

      // Sanity check: A's data is really there before we test the fix
      // against it — a test that "passes" against empty state either way
      // proves nothing.
      expect(container.read(goalsProvider).value?.weightGoalKg, 82);
      expect(container.read(chatProvider).messages, isNotEmpty);
      expect(container.read(inferenceProvider).recommendedDose, greaterThan(0));
      expect(container.read(deviceListProvider).value?.single.deviceId, 'device-a');
      expect(fakeApi.devicesFetchCount, 1);

      // ── User A logs out ──────────────────────────────────────────────────
      await container.read(authProvider.notifier).logout();

      // ── User B logs in — same process, no app restart ──────────────────
      fakeApi.respondingAs = 'b';
      await container.read(authProvider.notifier).login('b@example.com', 'pw');

      // ── None of A's data may still be visible ───────────────────────────
      expect(
        container.read(goalsProvider).value?.weightGoalKg,
        isNull,
        reason: "user A's weight goal leaked into user B's session",
      );
      expect(
        container.read(chatProvider).messages,
        isEmpty,
        reason: "user A's chat history leaked into user B's session",
      );
      expect(
        container.read(inferenceProvider).recommendedDose,
        0.0,
        reason: "user A's insulin dose recommendation leaked into user B's session",
      );

      // Devices: re-reading must trigger a genuine re-fetch (proving the
      // provider was actually torn down), not serve A's cached list back —
      // and the freshly-fetched list must reflect B, not A.
      final bDevices = await container.read(deviceListProvider.future);
      expect(
        fakeApi.devicesFetchCount,
        2,
        reason: 'device list was served from a stale cache instead of refetching for the new user',
      );
      expect(bDevices.single.deviceId, 'device-b');
    },
  );
}
