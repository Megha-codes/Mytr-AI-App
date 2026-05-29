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
import 'subproviders/dashboard_provider.dart';

// ── InsulinProvider ──────────────────────────────────────────────────────────
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
    totalBolusToday: 12.4, 
    adjustmentPercent: -15.0,
    lastBolusAmount: 4.5,
  );
});

// ── SleepProvider ────────────────────────────────────────────────────────────
enum SleepQuality { poor, fair, good, excellent }

class SleepState {
  final double lastNightHours;
  final SleepQuality quality;
  final List<SleepStage> stages;

  SleepState({
    required this.lastNightHours, 
    required this.quality,
    required this.stages,
  });
}

final sleepProvider = Provider<SleepState>((ref) {
  return SleepState(
    lastNightHours: 7.2, 
    quality: SleepQuality.good,
    stages: [
      SleepStage(type: SleepStageType.awake, hours: 0.5),
      SleepStage(type: SleepStageType.light, hours: 3.5),
      SleepStage(type: SleepStageType.deep, hours: 1.5),
      SleepStage(type: SleepStageType.rem, hours: 1.7),
    ],
  );
});

// ── WeightProvider ───────────────────────────────────────────────────────────
enum WeightUnit { kg, lbs }
enum ChangeDirection { up, down, stable }

class WeightState {
  final double currentWeight;
  final WeightUnit unit;
  final double weeklyChange;
  final ChangeDirection weeklyChangeDirection;

  WeightState({
    required this.currentWeight,
    required this.unit,
    required this.weeklyChange,
    required this.weeklyChangeDirection,
  });
}

final weightProvider = Provider<WeightState>((ref) {
  return WeightState(
    currentWeight: 78.4,
    unit: WeightUnit.kg,
    weeklyChange: 0.8,
    weeklyChangeDirection: ChangeDirection.down,
  );
});

// ── DeviceProvider ───────────────────────────────────────────────────────────
class WearableDevice {
  final String name;
  final String type;
  final DateTime lastSync;

  WearableDevice({required this.name, required this.type, required this.lastSync});
}

class DeviceState {
  final CGMDevice? connectedCGM;
  final List<WearableDevice> connectedWearables;

  DeviceState({this.connectedCGM, required this.connectedWearables});
}

final deviceProvider = Provider<DeviceState>((ref) {
  return DeviceState(
    connectedCGM: CGMDevice(
      id: 'cgm_1',
      name: 'Dexcom G7',
      status: SensorStatus.active,
      daysRemaining: 3,
    ),
    connectedWearables: [
      WearableDevice(name: 'Apple Watch', type: 'WATCH', lastSync: DateTime.now().subtract(const Duration(minutes: 5))),
    ],
  );
});

// ── ChallengesProvider ────────────────────────────────────────────────────────
// Derived synchronously from dashboardProvider — returns [] while loading.
final challengesProvider = Provider<List<Challenge>>((ref) {
  return ref.watch(dashboardProvider).valueOrNull?.challenges ?? [];
});
