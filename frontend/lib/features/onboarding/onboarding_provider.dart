import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/services/auth_storage_service.dart';

enum UserType {
  t1,
  t2,
  fitness,
}

class PersonalInfo {
  final String? fullName;
  final String? email;
  final String? password;
  final DateTime? dob;
  final String? gender;
  final double? weight;
  final double? height;
  final String? primaryGoal;

  PersonalInfo({
    this.fullName,
    this.email,
    this.password,
    this.dob,
    this.gender,
    this.weight,
    this.height,
    this.primaryGoal,
  });

  PersonalInfo copyWith({
    String? fullName,
    String? email,
    String? password,
    DateTime? dob,
    String? gender,
    double? weight,
    double? height,
    String? primaryGoal,
  }) {
    return PersonalInfo(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      password: password ?? this.password,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      weight: weight ?? this.weight,
      height: height ?? this.height,
      primaryGoal: primaryGoal ?? this.primaryGoal,
    );
  }
}

class InsulinProfile {
  final double? icr;
  final double? isf;
  final double? basalRate;
  final int? targetMin;
  final int? targetMax;
  final String? insulinType;
  final bool profileComplete;

  InsulinProfile({
    this.icr,
    this.isf,
    this.basalRate,
    this.targetMin,
    this.targetMax,
    this.insulinType,
    this.profileComplete = true,
  });

  InsulinProfile copyWith({
    double? icr,
    double? isf,
    double? basalRate,
    int? targetMin,
    int? targetMax,
    String? insulinType,
    bool? profileComplete,
  }) {
    return InsulinProfile(
      icr: icr ?? this.icr,
      isf: isf ?? this.isf,
      basalRate: basalRate ?? this.basalRate,
      targetMin: targetMin ?? this.targetMin,
      targetMax: targetMax ?? this.targetMax,
      insulinType: insulinType ?? this.insulinType,
      profileComplete: profileComplete ?? this.profileComplete,
    );
  }
}

class LifestyleBaseline {
  final String? sleepHrs;
  final String? activityLevel;
  final String? stressLevel;
  final String? calorieIntake;

  LifestyleBaseline({
    this.sleepHrs,
    this.activityLevel,
    this.stressLevel,
    this.calorieIntake,
  });

  LifestyleBaseline copyWith({
    String? sleepHrs,
    String? activityLevel,
    String? stressLevel,
    String? calorieIntake,
  }) {
    return LifestyleBaseline(
      sleepHrs: sleepHrs ?? this.sleepHrs,
      activityLevel: activityLevel ?? this.activityLevel,
      stressLevel: stressLevel ?? this.stressLevel,
      calorieIntake: calorieIntake ?? this.calorieIntake,
    );
  }
}

class DeviceSetup {
  final String? cgmDevice;
  final bool manualEntry;
  final List<String> wearables;

  DeviceSetup({
    this.cgmDevice,
    this.manualEntry = false,
    this.wearables = const [],
  });

  DeviceSetup copyWith({
    String? cgmDevice,
    bool? manualEntry,
    List<String>? wearables,
  }) {
    return DeviceSetup(
      cgmDevice: cgmDevice ?? this.cgmDevice,
      manualEntry: manualEntry ?? this.manualEntry,
      wearables: wearables ?? this.wearables,
    );
  }
}

class OnboardingState {
  final UserType? userType;
  final PersonalInfo? personalInfo;
  final InsulinProfile? insulinProfile;
  final LifestyleBaseline? lifestyleBaseline;
  final DeviceSetup? deviceSetup;
  final bool consentConfirmed;
  final bool researchConsent;
  final bool termsAccepted;

  OnboardingState({
    this.userType,
    this.personalInfo,
    this.insulinProfile,
    this.lifestyleBaseline,
    this.deviceSetup,
    this.consentConfirmed = false,
    this.researchConsent = true,
    this.termsAccepted = false,
  });

  OnboardingState copyWith({
    UserType? userType,
    PersonalInfo? personalInfo,
    InsulinProfile? insulinProfile,
    LifestyleBaseline? lifestyleBaseline,
    DeviceSetup? deviceSetup,
    bool? consentConfirmed,
    bool? researchConsent,
    bool? termsAccepted,
  }) {
    return OnboardingState(
      userType: userType ?? this.userType,
      personalInfo: personalInfo ?? this.personalInfo,
      insulinProfile: insulinProfile ?? this.insulinProfile,
      lifestyleBaseline: lifestyleBaseline ?? this.lifestyleBaseline,
      deviceSetup: deviceSetup ?? this.deviceSetup,
      consentConfirmed: consentConfirmed ?? this.consentConfirmed,
      researchConsent: researchConsent ?? this.researchConsent,
      termsAccepted: termsAccepted ?? this.termsAccepted,
    );
  }
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => OnboardingState();

  void setUserType(UserType type) {
    state = state.copyWith(userType: type);
    AuthStorageService().saveUserType(type.name);
    AuthStorageService().saveOnboardingStep(2);
  }

  void setPersonalInfo(PersonalInfo info) {
    state = state.copyWith(personalInfo: info);
    AuthStorageService().saveOnboardingStep(3);
  }

  void setInsulinProfile(InsulinProfile profile) {
    state = state.copyWith(insulinProfile: profile);
    AuthStorageService().saveOnboardingStep(4);
  }

  void setLifestyleBaseline(LifestyleBaseline baseline) {
    state = state.copyWith(lifestyleBaseline: baseline);
    AuthStorageService().saveOnboardingStep(5);
  }

  void setDeviceSetup(DeviceSetup setup) {
    state = state.copyWith(deviceSetup: setup);
    AuthStorageService().saveOnboardingStep(6);
  }

  void setConsent(bool confirmed, bool researchConsent, {bool termsAccepted = false}) {
    state = state.copyWith(
      consentConfirmed: confirmed,
      researchConsent: researchConsent,
      termsAccepted: termsAccepted,
    );
    AuthStorageService().saveOnboardingStep(7);
  }
  
  Future<Map<String, dynamic>?> submit() async {
    // Map UserType enum to the diabetes_type string the backend stores.
    final diabetesType = switch (state.userType) {
      UserType.t1      => 'T1',
      UserType.t2      => 'T2',
      UserType.fitness => null,
      null             => null,
    };

    final payload = {
      // Identity
      "user_type":   state.userType?.name.toUpperCase(),
      "diabetes_type": diabetesType,
      "email":       state.personalInfo?.email,
      "password":    state.personalInfo?.password,
      "name":        state.personalInfo?.fullName,
      "dob":         state.personalInfo?.dob?.toIso8601String().split('T')[0],
      "gender":      state.personalInfo?.gender,
      "weight_kg":   state.personalInfo?.weight,
      "height_cm":   state.personalInfo?.height,
      "primary_goal": state.personalInfo?.primaryGoal,
      // Insulin profile — flat fields matching UserOnboardRequest schema
      if (state.userType != UserType.fitness) ...{
        "icr":                state.insulinProfile?.icr,
        "isf":                state.insulinProfile?.isf,
        "basal_rate":         state.insulinProfile?.basalRate,
        "target_glucose_min": state.insulinProfile?.targetMin,
        "target_glucose_max": state.insulinProfile?.targetMax,
        "insulin_type":       state.insulinProfile?.insulinType,
      },
      // Lifestyle — flat fields (backend expects avg_sleep, not sleep_hrs)
      "avg_sleep":      state.lifestyleBaseline?.sleepHrs,
      "activity_level": state.lifestyleBaseline?.activityLevel,
      "stress_level":   state.lifestyleBaseline?.stressLevel,
      // Device
      "cgm_device": state.deviceSetup?.cgmDevice,
      // Consent
      "consent_confirmed_at": DateTime.now().toIso8601String(),
      "research_consent":     state.researchConsent,
      "terms_accepted":       state.termsAccepted,
    };

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post('/users/onboard', data: payload);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw Exception("An account with this email already exists.");
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

final onboardingProvider = NotifierProvider<OnboardingNotifier, OnboardingState>(() {
  return OnboardingNotifier();
});
