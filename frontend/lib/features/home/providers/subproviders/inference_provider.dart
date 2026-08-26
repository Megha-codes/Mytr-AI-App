import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../models/models.dart';

class InferenceState {
  final double recommendedDose;
  final double baseBolus;
  final double lifestyleAdjustmentPercent;
  final List<String> drivers;
  final double confidence;
  final bool showDoctorFlag;
  final bool isModelPersonalised;
  final bool isLoading;

  InferenceState({
    this.recommendedDose = 0.0,
    this.baseBolus = 0.0,
    this.lifestyleAdjustmentPercent = 0.0,
    this.drivers = const [],
    this.confidence = 0.0,
    this.showDoctorFlag = false,
    this.isModelPersonalised = false,
    this.isLoading = false,
  });

  InferenceState copyWith({
    double? recommendedDose,
    double? baseBolus,
    double? lifestyleAdjustmentPercent,
    List<String>? drivers,
    double? confidence,
    bool? showDoctorFlag,
    bool? isModelPersonalised,
    bool? isLoading,
  }) {
    return InferenceState(
      recommendedDose: recommendedDose ?? this.recommendedDose,
      baseBolus: baseBolus ?? this.baseBolus,
      lifestyleAdjustmentPercent: lifestyleAdjustmentPercent ?? this.lifestyleAdjustmentPercent,
      drivers: drivers ?? this.drivers,
      confidence: confidence ?? this.confidence,
      showDoctorFlag: showDoctorFlag ?? this.showDoctorFlag,
      isModelPersonalised: isModelPersonalised ?? this.isModelPersonalised,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class InferenceNotifier extends AutoDisposeNotifier<InferenceState> {
  @override
  InferenceState build() {
    return InferenceState();
  }

  Future<void> computeRecommendation(LoggedMeal meal) async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await ref.read(apiClientProvider).post(
        '/inference/bolus',
        data: {
          'name': meal.name,
          'calories': meal.calories,
          'carbs_g': meal.carbsG,
          'protein_g': meal.proteinG,
          'fat_g': meal.fatG,
        },
      );
      
      final data = response.data;
      state = state.copyWith(
        isLoading: false,
        recommendedDose: (data['recommended_dose'] as num).toDouble(),
        baseBolus: (data['base_bolus'] as num).toDouble(),
        lifestyleAdjustmentPercent: (data['lifestyle_adjustment_percent'] as num).toDouble(),
        drivers: List<String>.from(data['drivers']),
        confidence: (data['confidence'] as num).toDouble(),
        showDoctorFlag: data['show_doctor_flag'] ?? false,
        isModelPersonalised: data['is_personalised'] ?? false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  void reset() {
    state = InferenceState();
  }
}

// autoDispose: recommendedDose/baseBolus are a computed insulin dose
// recommendation for the signed-in user's own physiology and meal — this is
// dosing guidance, not just a display preference. Leaving a stale one alive
// into the next signed-in user's session (same device, no app restart on
// logout) isn't just a privacy leak, it's User B looking at a dose number
// computed for User A.
final inferenceProvider =
    NotifierProvider.autoDispose<InferenceNotifier, InferenceState>(() {
  return InferenceNotifier();
});
