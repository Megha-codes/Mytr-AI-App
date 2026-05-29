import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../onboarding_provider.dart';
import '../widgets/onboarding_layout.dart';

class LifestyleScreen extends ConsumerStatefulWidget {
  const LifestyleScreen({super.key});

  @override
  ConsumerState<LifestyleScreen> createState() => _LifestyleScreenState();
}

class _LifestyleScreenState extends ConsumerState<LifestyleScreen> {
  String? _sleepHrs;
  String? _activityLevel;
  String? _stressLevel;
  String? _calorieIntake;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final isFitness = state.userType == UserType.fitness;
    final currentStep = isFitness ? 4 : 5;

    final allAnswered = _sleepHrs != null &&
        _activityLevel != null &&
        _stressLevel != null &&
        _calorieIntake != null;

    return OnboardingLayout(
      currentStep: currentStep + 1, // Layout requires 1-based index (e.g. 5 of 7)
      sectionLabel: 'Lifestyle Baseline',
      title: 'Tell us about\nyour routine.',
      subtitle: 'These values seed the inference engine before it has real sensor data.',
      bottomCta: PrimaryButton(
        text: 'Continue →',
        variant: ButtonVariant.tertiary,
        onPressed: allAnswered
            ? () {
                final baseline = LifestyleBaseline(
                  sleepHrs: _sleepHrs,
                  activityLevel: _activityLevel,
                  stressLevel: _stressLevel,
                  calorieIntake: _calorieIntake,
                );
                ref.read(onboardingProvider.notifier).setLifestyleBaseline(baseline);
                context.push('/onboarding/devices');
              }
            : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildQuestionBlock(
            question: 'Average sleep per night?',
            options: ['< 5 hrs', '5–6 hrs', '7–8 hrs', '> 8 hrs'],
            selectedValue: _sleepHrs,
            selectedBgColor: AppColors.nearBlack,
            selectedTextColor: Colors.white,
            onSelect: (val) => setState(() => _sleepHrs = val),
          ),
          const SizedBox(height: 24),
          _buildQuestionBlock(
            question: 'Typical activity level?',
            options: ['Sedentary', 'Light', 'Moderate', 'Active'],
            selectedValue: _activityLevel,
            selectedBgColor: AppColors.limeAccent,
            selectedTextColor: const Color(0xFF1A3A08),
            onSelect: (val) => setState(() => _activityLevel = val),
          ),
          const SizedBox(height: 24),
          _buildQuestionBlock(
            question: 'Average daily stress?',
            options: ['Low', 'Moderate', 'High'],
            selectedValue: _stressLevel,
            selectedBgColor: AppColors.vividOrange,
            selectedTextColor: Colors.white,
            onSelect: (val) => setState(() => _stressLevel = val),
          ),
          const SizedBox(height: 24),
          _buildQuestionBlock(
            question: 'Approx. daily calorie intake?',
            options: ['< 1500', '1500–2000', '2000–2500', '> 2500'],
            selectedValue: _calorieIntake,
            selectedBgColor: AppColors.cyan,
            selectedTextColor: Colors.white,
            onSelect: (val) => setState(() => _calorieIntake = val),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionBlock({
    required String question,
    required List<String> options,
    required String? selectedValue,
    required Color selectedBgColor,
    required Color selectedTextColor,
    required Function(String) onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: const TextStyle(
            color: AppColors.nearBlack,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final isSelected = selectedValue == option;
            return GestureDetector(
              onTap: () => onSelect(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? selectedBgColor : Colors.white,
                  border: Border.all(
                    color: isSelected ? Colors.transparent : AppColors.borderLight,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  option + (isSelected ? ' ✓' : ''),
                  style: TextStyle(
                    color: isSelected ? selectedTextColor : const Color(0xFF888888),
                    fontSize: 9,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
