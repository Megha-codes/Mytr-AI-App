import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';
import '../../onboarding_provider.dart';

class OnboardingLayout extends ConsumerWidget {
  final int currentStep;
  final String title;
  final String? subtitle;
  final String? eyebrowText;
  final Color? eyebrowColor;
  final String? sectionLabel;
  final Widget body;
  final Widget bottomCta;

  const OnboardingLayout({
    super.key,
    required this.currentStep,
    required this.title,
    this.subtitle,
    this.eyebrowText,
    this.eyebrowColor,
    this.sectionLabel,
    required this.body,
    required this.bottomCta,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final isFitness = state.userType == UserType.fitness;
    final totalSteps = isFitness ? 7 : 8;
    
    // Automatically determine eyebrow text if not provided
    final calculatedEyebrow = eyebrowText ?? 'STEP $currentStep OF $totalSteps';
    final calculatedEyebrowColor = eyebrowColor ?? AppColors.limeAccent;

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dark header section
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          if (GoRouter.of(context).canPop())
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: GestureDetector(
                                onTap: () => context.pop(),
                                child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
                              ),
                            ),
                          Text(
                            calculatedEyebrow,
                            style: TextStyle(
                              color: calculatedEyebrowColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      _StepIndicator(
                        currentStep: currentStep,
                        totalSteps: totalSteps,
                      ),
                    ],
                  ),
                  if (sectionLabel != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      sectionLabel!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ] else ...[
                    const SizedBox(height: 16),
                  ],
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: sectionLabel != null ? Colors.white.withValues(alpha: 0.35) : AppColors.textSecondary,
                        fontSize: sectionLabel != null ? 9 : 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Cream body section
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: body,
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: bottomCta,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepIndicator({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalSteps, (index) {
        final stepNumber = index + 1;
        Color barColor;
        
        if (stepNumber < currentStep) {
          barColor = AppColors.limeAccent; // Completed
        } else if (stepNumber == currentStep) {
          barColor = Colors.white.withValues(alpha: 0.60); // Current
        } else {
          barColor = Colors.white.withValues(alpha: 0.15); // Future
        }

        return Container(
          width: 16,
          height: 3,
          margin: EdgeInsets.only(left: index == 0 ? 0 : 4),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }
}
