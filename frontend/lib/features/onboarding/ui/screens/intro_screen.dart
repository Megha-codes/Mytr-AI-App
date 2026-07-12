import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo Section
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.limeAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(LucideIcons.droplet, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Mytr.AI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Header Text
                    const Text(
                      'HEALTH. INTELLIGENTLY.',
                      style: TextStyle(
                        color: AppColors.limeAccent,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'One app for\nevery health\njourney.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'From glucose management to calorie tracking,\ncoaching and fitness — Mytr.AI adapts to your goals.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.38),
                        fontSize: 12,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 2x2 Feature Grid
                    Row(
                      children: [
                        Expanded(
                          child: _buildFeatureTile(
                            color: AppColors.limeAccent,
                            icon: '📡',
                            title: 'CGM Live',
                            subtitle: 'Real-time glucose',
                            titleColor: AppColors.nearBlack,
                            subColor: AppColors.nearBlack.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildFeatureTile(
                            color: AppColors.vividOrange,
                            icon: '🍽',
                            title: 'Calorie AI',
                            subtitle: 'Photo meal scan',
                            titleColor: AppColors.nearBlack,
                            subColor: AppColors.nearBlack.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFeatureTile(
                            color: AppColors.cyan,
                            icon: '⚡',
                            title: 'Bolus AI',
                            subtitle: 'Smart dose calc',
                            titleColor: AppColors.nearBlack,
                            subColor: AppColors.nearBlack.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildFeatureTile(
                            color: const Color(0xFF222222),
                            borderColor: const Color(0xFF333333),
                            icon: '🏃',
                            title: 'Fitness Coach',
                            subtitle: 'Activity & sleep',
                            titleColor: Colors.white,
                            subColor: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Feature Pills Row
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildPill('Weight tracking'),
                        _buildPill('Sleep insights'),
                        _buildPill('Stress tracking'),
                        _buildPill('XP & challenges'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Cream Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
              decoration: const BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PrimaryButton(
                    text: 'Get Started — It\'s Free →',
                    variant: ButtonVariant.tertiary,
                    onPressed: () => context.push('/onboarding/create-account'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => context.push('/auth/login'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.nearBlack,
                        side: const BorderSide(color: AppColors.nearBlack, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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

  Widget _buildFeatureTile({
    required Color color,
    Color? borderColor,
    required String icon,
    required String title,
    required String subtitle,
    required Color titleColor,
    required Color subColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(11),
        border: borderColor != null ? Border.all(color: borderColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: titleColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: subColor,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 9,
        ),
      ),
    );
  }
}