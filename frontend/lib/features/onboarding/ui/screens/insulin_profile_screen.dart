import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import 'package:reactive_forms/reactive_forms.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../onboarding_provider.dart';
import '../widgets/onboarding_layout.dart';

class InsulinProfileScreen extends ConsumerStatefulWidget {
  const InsulinProfileScreen({super.key});

  @override
  ConsumerState<InsulinProfileScreen> createState() => _InsulinProfileScreenState();
}

class _InsulinProfileScreenState extends ConsumerState<InsulinProfileScreen> {
  bool _isUnknown = false;

  final FormGroup form = FormGroup({
    'icr': FormControl<double>(validators: [Validators.min(1), Validators.max(50)]),
    'isf': FormControl<double>(validators: [Validators.min(10), Validators.max(200)]),
    'basalRate': FormControl<double>(validators: [Validators.min(0.05), Validators.max(5.0)]),
    'targetMin': FormControl<int>(value: 80),
    'targetMax': FormControl<int>(value: 130),
    'insulinType': FormControl<String>(),
  }, validators: [const TargetMinMaxValidator()]);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final isT1 = state.userType == UserType.t1;

    return ReactiveForm(
      formGroup: form,
      child: OnboardingLayout(
        currentStep: 4,
      eyebrowText: 'STEP 4 OF 8 · DIABETES ONLY',
      eyebrowColor: AppColors.cyan,
      sectionLabel: 'Medical Profile',
      title: 'Insulin Profile',
      subtitle: 'Enter your prescribed values. If unsure, you can skip for now.',
      bottomCta: ReactiveFormConsumer(
        builder: (context, form, child) {
          final isFormValid = _isUnknown || form.valid;
          return PrimaryButton(
            text: _isUnknown ? 'Skip for now →' : 'Continue →',
            variant: ButtonVariant.tertiary,
            onPressed: isFormValid
                ? () {
                    final data = form.value;
                    final profile = InsulinProfile(
                      icr: _isUnknown ? null : data['icr'] as double?,
                      isf: _isUnknown ? null : data['isf'] as double?,
                      basalRate: _isUnknown ? null : data['basalRate'] as double?,
                      targetMin: _isUnknown ? null : data['targetMin'] as int?,
                      targetMax: _isUnknown ? null : data['targetMax'] as int?,
                      insulinType: _isUnknown ? null : data['insulinType'] as String?,
                      profileComplete: !_isUnknown,
                    );
                    ref.read(onboardingProvider.notifier).setInsulinProfile(profile);
                    context.push('/onboarding/lifestyle');
                  }
                : null,
          );
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "I don't know this yet" toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'I don\'t know this yet',
                        style: TextStyle(
                          color: AppColors.nearBlack,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Locks the bolus calculator until completed.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoSwitch(
                  value: _isUnknown,
                  activeTrackColor: AppColors.limeAccent,
                  onChanged: (val) {
                    setState(() {
                      _isUnknown = val;
                      if (val) {
                        form.markAsDisabled();
                      } else {
                        form.markAsEnabled();
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          Opacity(
            opacity: _isUnknown ? 0.5 : 1.0,
            child: Column(
              children: [
                _buildFieldCard(
                    label: 'Insulin-to-Carb Ratio (ICR)',
                    child: ReactiveTextField<double>(
                      formControlName: 'icr',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputDecoration('1 : __ g'),
                    ),
                    onInfoTap: () => _showInfoSheet(context, 'ICR tells the app how many grams of carbohydrate 1 unit of insulin covers. Get this from your endocrinologist.'),
                  ),
                  const SizedBox(height: 12),
                  _buildFieldCard(
                    label: 'Insulin Sensitivity Factor (ISF)',
                    child: ReactiveTextField<double>(
                      formControlName: 'isf',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputDecoration('e.g. 50').copyWith(suffixText: 'mg/dL per unit'),
                    ),
                    onInfoTap: () => _showInfoSheet(context, 'ISF is how much 1 unit of insulin lowers your glucose in mg/dL. Get this from your endocrinologist.'),
                  ),
                  if (isT1) ...[
                    const SizedBox(height: 12),
                    _buildFieldCard(
                      label: 'Basal Rate (units/hr)',
                      child: ReactiveTextField<double>(
                        formControlName: 'basalRate',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('e.g. 1.5').copyWith(suffixText: 'units/hr'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFieldCard(
                          label: 'Target Min',
                          child: ReactiveTextField<int>(
                            formControlName: 'targetMin',
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration('80').copyWith(suffixText: 'mg/dL'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFieldCard(
                          label: 'Target Max',
                          child: ReactiveTextField<int>(
                            formControlName: 'targetMax',
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration('130').copyWith(suffixText: 'mg/dL'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildFieldCard(
                    label: 'Rapid-acting Insulin Type',
                    child: ReactiveDropdownField<String>(
                      formControlName: 'insulinType',
                      decoration: _inputDecoration('Select Type').copyWith(
                        suffixIcon: const Icon(LucideIcons.chevronDown, size: 20, color: AppColors.textSecondary),
                      ),
                      icon: const SizedBox.shrink(),
                      items: ['Humalog', 'NovoLog', 'Fiasp', 'Apidra', 'Other']
                          .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                          .toList(),
                    ),
                  ),
                ],
              ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildFieldCard({required String label, required Widget child, VoidCallback? onInfoTap}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.nearBlack,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onInfoTap != null)
                GestureDetector(
                  onTap: _isUnknown ? null : onInfoTap,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: const Icon(LucideIcons.info, size: 12, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      filled: true,
      fillColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
    );
  }

  void _showInfoSheet(BuildContext context, String message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(32.0),
        child: Text(
          message,
          style: const TextStyle(
            color: AppColors.nearBlack,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class TargetMinMaxValidator extends Validator<dynamic> {
  const TargetMinMaxValidator();

  @override
  Map<String, dynamic>? validate(AbstractControl<dynamic> control) {
    final form = control as FormGroup;
    final min = form.control('targetMin').value as int?;
    final max = form.control('targetMax').value as int?;
    if (min != null && max != null && min >= max) {
      return {'minMaxError': true};
    }
    return null;
  }
}
