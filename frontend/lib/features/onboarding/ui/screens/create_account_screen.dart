import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reactive_forms/reactive_forms.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/api/api_client.dart';
import '../../onboarding_provider.dart';
import '../widgets/onboarding_layout.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:dio/dio.dart';

class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isCheckingEmail = false;

  final FormGroup form = FormGroup({
    'fullName': FormControl<String>(validators: [Validators.required, Validators.minLength(2)]),
    'email': FormControl<String>(validators: [Validators.required, Validators.email]),
    'password': FormControl<String>(validators: [
      Validators.required, 
      Validators.minLength(8), 
      Validators.pattern(RegExp(r'.*[0-9].*'), validationMessage: 'must contain a number')
    ]),
    'confirmPassword': FormControl<String>(validators: [Validators.required]),
  }, validators: [
    const MustMatchValidator('password', 'confirmPassword', true)
  ]);

  int _calculatePasswordStrength(String password) {
    if (password.isEmpty) return 0;
    int score = 0;
    if (password.length > 5) score++;
    if (password.length > 7) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) || RegExp(r'[!@#\$%\^&\*]').hasMatch(password)) score++;
    return score; // 0 to 4
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
                  isLoading: _isCheckingEmail,
                  onPressed: form.valid && !_isCheckingEmail
                      ? () async {
                          final data = form.value;
                          final email = data['email'] as String;
                          
                          setState(() {
                            _isCheckingEmail = true;
                          });

                          try {
                            final apiClient = ref.read(apiClientProvider);
                            final response = await apiClient.get('/users/auth/check-email', queryParameters: {'email': email});
                            
                            if (response.data['exists'] == true) {
                              if (context.mounted) {
                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: AppColors.surfaceWhite,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                  ),
                                  builder: (context) => Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        const Text(
                                          'Account already exists',
                                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.nearBlack),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'An account with $email already exists. Would you like to sign in instead?',
                                          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                                        ),
                                        const SizedBox(height: 24),
                                        PrimaryButton(
                                          text: 'Sign In',
                                          variant: ButtonVariant.primary,
                                          onPressed: () {
                                            context.pop(); // close sheet
                                            context.go('/auth/login', extra: email);
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        PrimaryButton(
                                          text: 'Use a different email',
                                          variant: ButtonVariant.secondary,
                                          onPressed: () {
                                            context.pop();
                                            form.control('email').value = '';
                                          },
                                        ),
                                        const SizedBox(height: 24),
                                      ],
                                    ),
                                  ),
                                );
                              }
                            } else {
                              // Success - email is available
                              if (context.mounted) {
                                final info = PersonalInfo(
                                  fullName: data['fullName'] as String?,
                                  email: email,
                                  password: data['password'] as String?,
                                );
                                
                                final currentState = ref.read(onboardingProvider);
                                ref.read(onboardingProvider.notifier).setPersonalInfo(
                                  currentState.personalInfo?.copyWith(
                                    fullName: info.fullName,
                                    email: info.email,
                                    password: info.password,
                                  ) ?? info,
                                );
                                context.push('/onboarding/user-type');
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: ${e.toString()}')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isCheckingEmail = false);
                          }
                        }
                      : null,
                );
              },
            ),
            const SizedBox(height: 20),
            Center(
              child: GestureDetector(
                onTap: () {
                  context.go('/auth/login');
                },
                child: RichText(
                  text: const TextSpan(
                    text: 'Already have an account? ',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text: 'Sign in',
                        style: TextStyle(
                          color: AppColors.nearBlack,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                'pattern': (error) => 'Must contain at least 1 number',
              },
              decoration: _inputDecoration('Min 8 chars, 1 number').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            
            // Password strength bar
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
                    _obscureConfirmPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
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
