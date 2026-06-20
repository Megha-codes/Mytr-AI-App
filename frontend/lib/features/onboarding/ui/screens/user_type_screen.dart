import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../onboarding_provider.dart';
import '../widgets/onboarding_layout.dart';

class UserTypeScreen extends ConsumerWidget {
  const UserTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedType = state.userType;

    return OnboardingLayout(
      currentStep: 2,
      title: 'What brings you\nto Mytr.AI?',
      subtitle: 'We\'ll personalise your experience.',
      bottomCta: PrimaryButton(
        text: 'Continue →',
        variant: ButtonVariant.tertiary,
        onPressed: selectedType != null
            ? () => context.push('/onboarding/personal-info')
            : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UserTypeCard(
            type: UserType.t1,
            selected: selectedType == UserType.t1,
            iconBgColor: AppColors.cyan,
            emoji: '💉',
            title: 'Type 1 Diabetes',
            subtitle: 'Insulin-dependent',
            pills: const ['CGM Live', 'Bolus AI', 'Insulin Coach'],
            pillBgColor: AppColors.cyan.withValues(alpha: 0.2),
            pillTextColor: AppColors.cyan,
            onTap: () => ref.read(onboardingProvider.notifier).setUserType(UserType.t1),
          ),
          const SizedBox(height: 8),
          _UserTypeCard(
            type: UserType.t2,
            selected: selectedType == UserType.t2,
            iconBgColor: AppColors.vividOrange,
            emoji: '🩸',
            title: 'Type 2 Diabetes',
            subtitle: 'Oral meds or lifestyle-managed',
            pills: const ['Glucose Track', 'Meal AI', 'Lifestyle Coach'],
            pillBgColor: const Color(0xFFFEF0E6),
            pillTextColor: AppColors.vividOrange,
            onTap: () => ref.read(onboardingProvider.notifier).setUserType(UserType.t2),
          ),
          const SizedBox(height: 8),
          _UserTypeCard(
            type: UserType.fitness,
            selected: selectedType == UserType.fitness,
            iconBgColor: AppColors.limeAccent,
            emoji: '🏃',
            title: 'Fitness Enthusiast',
            subtitle: 'Health tracking & coaching',
            pills: const ['Calorie AI', 'Activity', 'Body Goals', 'Coaching'],
            pillBgColor: const Color(0xFFF0FDE4),
            pillTextColor: const Color(0xFF3B7D0E),
            onTap: () => ref.read(onboardingProvider.notifier).setUserType(UserType.fitness),
          ),
        ],
      ),
    );
  }
}

class _UserTypeCard extends StatelessWidget {
  final UserType type;
  final bool selected;
  final Color iconBgColor;
  final String emoji;
  final String title;
  final String subtitle;
  final List<String> pills;
  final Color pillBgColor;
  final Color pillTextColor;
  final VoidCallback onTap;

  const _UserTypeCard({
    required this.type,
    required this.selected,
    required this.iconBgColor,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.pills,
    required this.pillBgColor,
    required this.pillTextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.nearBlack : AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? iconBgColor : AppColors.borderLight,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(emoji, style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: selected ? Colors.white : AppColors.nearBlack,
                            fontSize: 13, // Slightly bumped from 11 for readability
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: selected ? Colors.white.withValues(alpha: 0.4) : AppColors.textSecondary,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: pills.map((p) => _buildPill(p)).toList(),
                ),
              ],
            ),
            if (selected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(LucideIcons.check, color: Colors.white, size: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: pillBgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: pillTextColor,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
