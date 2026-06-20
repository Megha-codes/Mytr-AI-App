export 'subproviders/dashboard_provider.dart';
export 'subproviders/glucose_provider.dart';
export 'subproviders/nutrition_provider.dart';
export 'subproviders/activity_provider.dart';
export 'subproviders/coach_provider.dart';
export 'subproviders/meal_recognition_provider.dart';
export 'subproviders/inference_provider.dart';
export '../models/models.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../../profile/providers/user_profile_provider.dart';
import '../../wearables/providers/wearable_provider.dart';
import 'subproviders/dashboard_provider.dart';

// ── InsulinProvider ──────────────────────────────────────────────────────────
// No bolus data source is wired yet, so totals are zero until insulin logging
// (or pump sync) exists. No fabricated values.
class InsulinState {
  final double totalBolusToday;
  final double adjustmentPercent;
  final double lastBolusAmount;

  InsulinState({
    required this.totalBolusToday,
    required this.adjustmentPercent,
    required this.lastBolusAmount,
  });
}

final insulinProvider = Provider<InsulinState>((ref) {
  return InsulinState(
    totalBolusToday: 0,
    adjustmentPercent: 0,
    lastBolusAmount: 0,
  );
});

// ── SleepProvider ────────────────────────────────────────────────────────────
// Sleep requires a connected wearable/Health source. Until one is connected,
// `hasData` is false and the UI hides sleep cards instead of showing fake data.
enum SleepQuality { poor, fair, good, excellent }

class SleepState {
  final bool hasData;
  final double lastNightHours;
  final SleepQuality quality;
  final List<SleepStage> stages;

  SleepState({
    this.hasData = false,
    this.lastNightHours = 0,
    this.quality = SleepQuality.fair,
    this.stages = const [],
  });
}

final sleepProvider = Provider<SleepState>((ref) {
  // No wearable/Health Connect sync implemented yet → no sleep data.
  return SleepState(hasData: false);
});

// ── WeightProvider ───────────────────────────────────────────────────────────
// Current weight comes from the real profile the user entered at onboarding.
// Weekly change stays 0 until weight logging history exists.
enum WeightUnit { kg, lbs }
enum ChangeDirection { up, down, stable }

class WeightState {
  final bool hasData;
  final double currentWeight;
  final WeightUnit unit;
  final double weeklyChange;
  final ChangeDirection weeklyChangeDirection;

  WeightState({
    this.hasData = false,
    this.currentWeight = 0,
    this.unit = WeightUnit.kg,
    this.weeklyChange = 0,
    this.weeklyChangeDirection = ChangeDirection.stable,
  });
}

final weightProvider = Provider<WeightState>((ref) {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  final w = profile?.startingWeight ?? 0;
  if (w <= 0) return WeightState(hasData: false);
  return WeightState(
    hasData: true,
    currentWeight: w,
    unit: WeightUnit.kg,
    weeklyChange: 0,
    weeklyChangeDirection: ChangeDirection.stable,
  );
});

// ── DeviceProvider ───────────────────────────────────────────────────────────
// No device pairing flow is wired yet, so nothing is reported as connected.
// The UI shows honest "connect a device" prompts instead of fake devices.
class WearableDevice {
  final String name;
  final String type;
  final DateTime lastSync;

  WearableDevice({required this.name, required this.type, required this.lastSync});
}

class DeviceState {
  final CGMDevice? connectedCGM;
  final List<WearableDevice> connectedWearables;

  DeviceState({this.connectedCGM, this.connectedWearables = const []});
}

final deviceProvider = Provider<DeviceState>((ref) {
  final wearables = ref.watch(wearableProvider).valueOrNull;
  final connected = <WearableDevice>[];

  if (wearables?.healthConnected == true) {
    connected.add(WearableDevice(
      name: wearables!.healthName,
      type: 'HEALTH',
      lastSync: wearables.healthLastSync ?? DateTime.now(),
    ));
  }
  if (wearables?.googleHealthConnected == true) {
    connected.add(WearableDevice(
      name: 'Fitbit',
      type: 'GOOGLE_HEALTH',
      lastSync: wearables!.googleHealthLastSync ?? DateTime.now(),
    ));
  }

  return DeviceState(connectedCGM: null, connectedWearables: connected);
});

// ── ChallengesProvider ────────────────────────────────────────────────────────
// Derived synchronously from dashboardProvider — returns [] while loading.
final challengesProvider = Provider<List<Challenge>>((ref) {
  return ref.watch(dashboardProvider).valueOrNull?.challenges ?? [];
});
