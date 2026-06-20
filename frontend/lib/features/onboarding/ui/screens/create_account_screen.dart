import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reactive_forms/reactive_forms.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../onboarding_provider.dart';
import '../widgets/onboarding_layout.dart';
import '../../../../core/icons/lucide_icons.dart';

class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final FormGroup form = FormGroup(
    {
      'fullName': FormControl<String>(
        validators: [Validators.required, Validators.minLength(2)],
      ),
      'email': FormControl<String>(
        validators: [Validators.required, Validators.email],
      ),
      'password': FormControl<String>(
        validators: [
          Validators.required,
          Validators.minLength(8),
          // Require at least one letter AND one number — mirrors the backend
          // password policy so a password accepted here won't be rejected
          // server-side.
          Validators.pattern(
            RegExp(r'^(?=.*[A-Za-z])(?=.*\d).+$'),
            validationMessage: 'must contain a letter and a number',
          ),
        ],
      ),
      'confirmPassword': FormControl<String>(validators: [Validators.required]),
    },
    validators: [const MustMatchValidator('password', 'confirmPassword', true)],
  );

  int _calculatePasswordStrength(String password) {
    if (password.isEmpty) return 0;
    int score = 0;
    if (password.length > 5) score++;
    if (password.length > 7) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) ||
        RegExp(r'[!@#\$%\^&\*]').hasMatch(password)) {
      score++;
    }
    return score;
  }

  @override
  Widget build(BuildContext context) {
    return ReactiveForm(
      formGroup: form,
      child: OnboardingLayout(
        currentStep: 1,
        title: 'Create your account',
        subtitle: 'You\'ll use these to log back in',
        bottomCta: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReactiveFormConsumer(
              builder: (context, form, child) {
                return PrimaryButton(
                  text: 'Continue →',
                  variant: ButtonVariant.primary,
                  onPressed: form.valid
                      ? () {
                          final data = form.value;
                          final info = PersonalInfo(
                            fullName: data['fullName'] as String?,
                            email: data['email'] as String,
                            password: data['password'] as String?,
                          );

                          final currentState = ref.read(onboardingProvider);
                          ref.read(onboardingProvider.notifier).setPersonalInfo(
                            currentState.personalInfo?.copyWith(
                                  fullName: info.fullName,
                                  email: info.email,
                                  password: info.password,
                                ) ??
                                info,
                          );
                          context.push('/onboarding/user-type');
                        }
                      : null,
                );
              },
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFieldLabel('FULL NAME'),
            ReactiveTextField<String>(
              formControlName: 'fullName',
              textInputAction: TextInputAction.next,
              validationMessages: {
                'required': (error) => 'Full name is required',
                'minLength': (error) => 'Name is too short',
              },
              decoration: _inputDecoration('e.g. Arjun Sharma'),
            ),
            const SizedBox(height: 16),
            _buildFieldLabel('EMAIL ADDRESS'),
            ReactiveTextField<String>(
              formControlName: 'email',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validationMessages: {
                'required': (error) => 'Email is required',
                'email': (error) => 'Please enter a valid email',
              },
              decoration: _inputDecoration('e.g. arjun@example.com'),
            ),
            const SizedBox(height: 16),
            _buildFieldLabel('PASSWORD'),
            ReactiveTextField<String>(
              formControlName: 'password',
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              validationMessages: {
                'required': (error) => 'Password is required',
                'minLength': (error) => 'Must be at least 8 characters',
                'pattern': (error) => 'Must contain a letter and a number',
              },
              decoration: _inputDecoration('Min 8 chars, 1 letter & 1 number').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            ReactiveValueListenableBuilder<String>(
              formControlName: 'password',
              builder: (context, control, child) {
                final password = control.value ?? '';
                final score = _calculatePasswordStrength(password);

                return Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Row(
                    children: List.generate(4, (index) {
                      Color color = AppColors.borderLight;
                      if (index < score) {
                        if (score <= 1) {
                          color = AppColors.vividOrange;
                        } else if (score == 2) {
                          color = Colors.orangeAccent;
                        } else if (score == 3) {
                          color = AppColors.limeAccent;
                        } else {
                          color = AppColors.cyan;
                        }
                      }

                      return Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsets.only(right: index < 3 ? 4 : 0),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _buildFieldLabel('CONFIRM PASSWORD'),
            ReactiveTextField<String>(
              formControlName: 'confirmPassword',
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              validationMessages: {
                'required': (error) => 'Please confirm your password',
                'mustMatch': (error) => 'Passwords do not match',
              },
              decoration: _inputDecoration('Re-enter password').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? LucideIcons.eyeOff
                        : LucideIcons.eye,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                ),
              ),
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