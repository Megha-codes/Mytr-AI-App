import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reactive_forms/reactive_forms.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../onboarding_provider.dart';
import '../widgets/onboarding_layout.dart';
import 'package:intl/intl.dart';

class PersonalInfoScreen extends ConsumerStatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  ConsumerState<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends ConsumerState<PersonalInfoScreen> {
  final FormGroup form = FormGroup({
    'dob': FormControl<DateTime>(validators: [Validators.required]),
    'gender': FormControl<String>(validators: [Validators.required]),
    'weight': FormControl<double>(validators: [Validators.required, Validators.min(20), Validators.max(300)]),
    'height': FormControl<double>(validators: [Validators.required, Validators.min(50), Validators.max(250)]),
    'primaryGoal': FormControl<String>(),
  });

  final List<String> goals = [
    'Manage glucose',
    'Lose weight',
    'Build fitness',
    'Eat healthier'
  ];

  @override
  Widget build(BuildContext context) {
    return ReactiveForm(
      formGroup: form,
      child: OnboardingLayout(
        currentStep: 3,
        title: 'Tell us about\nyourself',
        bottomCta: ReactiveFormConsumer(
        builder: (context, form, child) {
          return PrimaryButton(
            text: 'Continue →',
            variant: ButtonVariant.secondary, // Secondary is Cyan
            onPressed: form.valid
                ? () {
                    final data = form.value;
                      final state = ref.read(onboardingProvider);
                      final info = state.personalInfo?.copyWith(
                        dob: data['dob'] as DateTime?,
                        gender: data['gender'] as String?,
                        weight: data['weight'] as double?,
                        height: data['height'] as double?,
                        primaryGoal: data['primaryGoal'] as String?,
                      ) ?? PersonalInfo(
                        dob: data['dob'] as DateTime?,
                        gender: data['gender'] as String?,
                        weight: data['weight'] as double?,
                        height: data['height'] as double?,
                        primaryGoal: data['primaryGoal'] as String?,
                      );
                      ref.read(onboardingProvider.notifier).setPersonalInfo(info);
                      
                      if (state.userType == UserType.fitness) {
                      context.push('/onboarding/lifestyle');
                    } else {
                      context.push('/onboarding/insulin-profile');
                    }
                  }
                : null,
          );
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('DATE OF BIRTH'),
                      ReactiveDatePicker<DateTime>(
                        formControlName: 'dob',
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                        builder: (context, picker, child) {
                          return InkWell(
                            onTap: picker.showPicker,
                            child: InputDecorator(
                              decoration: _inputDecoration('DD MMM YYYY'),
                              child: Text(
                                picker.value != null
                                    ? DateFormat('dd MMM yyyy').format(picker.value!)
                                    : 'Select Date',
                                style: TextStyle(
                                  color: picker.value != null ? AppColors.nearBlack : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('GENDER'),
                      ReactiveDropdownField<String>(
                        formControlName: 'gender',
                        decoration: _inputDecoration('Select'),
                        items: ['Male', 'Female', 'Other', 'Prefer not to say']
                            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('WEIGHT'),
                      ReactiveTextField<double>(
                        formControlName: 'weight',
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('e.g. 68').copyWith(suffixText: 'kg'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('HEIGHT'),
                      ReactiveTextField<double>(
                        formControlName: 'height',
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('e.g. 174').copyWith(suffixText: 'cm'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildFieldLabel('PRIMARY GOAL'),
            ReactiveValueListenableBuilder<String>(
              formControlName: 'primaryGoal',
              builder: (context, control, child) {
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 3,
                  children: goals.map((goal) {
                    final isSelected = control.value == goal;
                    return GestureDetector(
                      onTap: () => control.value = goal,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.nearBlack : AppColors.cream,
                          border: Border.all(
                            color: isSelected ? AppColors.nearBlack : AppColors.borderLight,
                          ),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Center(
                          child: Text(
                            goal + (isSelected ? ' ✓' : ''),
                            style: TextStyle(
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      filled: true,
      fillColor: AppColors.surfaceWhite,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.limeAccent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.vividOrange),
      ),
    );
  }
}
