import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

enum UserType { t1, t2, fitness }

class OnboardingData {
  final UserType? userType;
  final String? diabetesType;
  final String? name;
  final DateTime? dob;
  final double? weightKg;
  final double? heightCm;
  final String? gender;
  final double? icr;
  final double? isf;
  final double? basalRate;
  final int? targetGlucoseMin;
  final int? targetGlucoseMax;
  final String? insulinType;
  final bool profileComplete;
  final String? cgmDevice;
  final double? baselineSleepHrs;
  final String? baselineActivityLevel;
  final String? baselineStressLevel;
  final int? baselineCalories;
  final DateTime? consentConfirmedAt;

  OnboardingData({
    this.userType,
    this.diabetesType,
    this.name,
    this.dob,
    this.weightKg,
    this.heightCm,
    this.gender,
    this.icr,
    this.isf,
    this.basalRate,
    this.targetGlucoseMin,
    this.targetGlucoseMax,
    this.insulinType,
    this.profileComplete = true,
    this.cgmDevice,
    this.baselineSleepHrs,
    this.baselineActivityLevel,
    this.baselineStressLevel,
    this.baselineCalories,
    this.consentConfirmedAt,
  });

  OnboardingData copyWith({
    UserType? userType,
    String? diabetesType,
    String? name,
    DateTime? dob,
    double? weightKg,
    double? heightCm,
    String? gender,
    double? icr,
    double? isf,
    double? basalRate,
    int? targetGlucoseMin,
    int? targetGlucoseMax,
    String? insulinType,
    bool? profileComplete,
    String? cgmDevice,
    double? baselineSleepHrs,
    String? baselineActivityLevel,
    String? baselineStressLevel,
    int? baselineCalories,
    DateTime? consentConfirmedAt,
  }) {
    return OnboardingData(
      userType: userType ?? this.userType,
      diabetesType: diabetesType ?? this.diabetesType,
      name: name ?? this.name,
      dob: dob ?? this.dob,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      gender: gender ?? this.gender,
      icr: icr ?? this.icr,
      isf: isf ?? this.isf,
      basalRate: basalRate ?? this.basalRate,
      targetGlucoseMin: targetGlucoseMin ?? this.targetGlucoseMin,
      targetGlucoseMax: targetGlucoseMax ?? this.targetGlucoseMax,
      insulinType: insulinType ?? this.insulinType,
      profileComplete: profileComplete ?? this.profileComplete,
      cgmDevice: cgmDevice ?? this.cgmDevice,
      baselineSleepHrs: baselineSleepHrs ?? this.baselineSleepHrs,
      baselineActivityLevel: baselineActivityLevel ?? this.baselineActivityLevel,
      baselineStressLevel: baselineStressLevel ?? this.baselineStressLevel,
      baselineCalories: baselineCalories ?? this.baselineCalories,
      consentConfirmedAt: consentConfirmedAt ?? this.consentConfirmedAt,
    );
  }
}

class OnboardingNotifier extends Notifier<OnboardingData> {
  @override
  OnboardingData build() => OnboardingData();

  void updateData(OnboardingData newData) => state = newData;

  void setUserType(UserType type) {
    state = state.copyWith(
      userType: type,
      diabetesType: type == UserType.t1 ? 'T1' : type == UserType.t2 ? 'T2' : null,
    );
  }

  void setPersonalInfo({
    String? name,
    DateTime? dob,
    double? weightKg,
    double? heightCm,
    String? gender,
  }) {
    state = state.copyWith(
      name: name,
      dob: dob,
      weightKg: weightKg,
      heightCm: heightCm,
      gender: gender,
    );
  }

  void setInsulinProfile({
    double? icr,
    double? isf,
    double? basalRate,
    int? targetGlucoseMin,
    int? targetGlucoseMax,
    String? insulinType,
  }) {
    state = state.copyWith(
      icr: icr,
      isf: isf,
      basalRate: basalRate,
      targetGlucoseMin: targetGlucoseMin,
      targetGlucoseMax: targetGlucoseMax,
      insulinType: insulinType,
    );
  }

  void setLifestyleBaseline({
    double? sleepHrs,
    String? activityLevel,
    String? stressLevel,
    int? calories,
  }) {
    state = state.copyWith(
      baselineSleepHrs: sleepHrs,
      baselineActivityLevel: activityLevel,
      baselineStressLevel: stressLevel,
      baselineCalories: calories,
    );
  }

  void setDeviceSetup({String? cgmDevice}) {
    state = state.copyWith(cgmDevice: cgmDevice);
  }

  void setConsent(bool medical, bool research) {
    state = state.copyWith(consentConfirmedAt: DateTime.now());
  }

  Future<Map<String, dynamic>?> submit() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final data = state;

      final String userTypeStr;
      switch (data.userType) {
        case UserType.t1:
          userTypeStr = 'T1';
          break;
        case UserType.t2:
          userTypeStr = 'T2';
          break;
        default:
          userTypeStr = 'FITNESS';
      }

      final response = await apiClient.post(
        '/api/v1/users/onboard',
        data: {
          'user_type': userTypeStr,
          'name': data.name ?? 'User',
          'diabetes_type': data.diabetesType,
          'icr': data.icr,
          'isf': data.isf,
          'basal_rate': data.basalRate,
          'target_glucose_min': data.targetGlucoseMin,
          'target_glucose_max': data.targetGlucoseMax,
          'insulin_type': data.insulinType,
          'cgm_device': data.cgmDevice,
          'avg_sleep': data.baselineSleepHrs,
          'activity_level': data.baselineActivityLevel,
          'stress_level': data.baselineStressLevel,
          'weight_kg': data.weightKg,
          'height_cm': data.heightCm,
          'gender': data.gender,
        },
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingData>(() {
  return OnboardingNotifier();
});