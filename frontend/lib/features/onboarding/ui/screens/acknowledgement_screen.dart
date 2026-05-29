import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/services/auth_storage_service.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../onboarding_provider.dart';
import '../widgets/onboarding_layout.dart';

class AcknowledgementScreen extends ConsumerStatefulWidget {
  const AcknowledgementScreen({super.key});

  @override
  ConsumerState<AcknowledgementScreen> createState() => _AcknowledgementScreenState();
}

class _AcknowledgementScreenState extends ConsumerState<AcknowledgementScreen> {
  bool _medicalDisclaimerChecked = false;
  bool _researchConsentChecked = true;
  bool _isSubmitting = false;

  Future<void> _submitAndNavigate() async {
    setState(() => _isSubmitting = true);
    
    // Save the final state
    ref.read(onboardingProvider.notifier).setConsent(_medicalDisclaimerChecked, _researchConsentChecked);
    
    // Call the backend
    final response = await ref.read(onboardingProvider.notifier).submit();
    
    if (context.mounted) {
      setState(() => _isSubmitting = false);
      if (response != null && response['access_token'] != null) {
        await ref.read(authProvider.notifier).completeOnboarding(
          response['access_token'],
          response['refresh_token'] ?? '',
        );
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong — please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final isFitness = state.userType == UserType.fitness;
    final stepText = isFitness ? 'STEP 7 OF 7' : 'STEP 8 OF 8';

    return OnboardingLayout(
      currentStep: isFitness ? 7 : 8, // Forces all bars to be filled/green
      eyebrowText: '$stepText · FINAL STEP',
      eyebrowColor: AppColors.limeAccent,
      title: 'Before you begin',
      bottomCta: PrimaryButton(
        text: 'I Agree — Start Mytr.AI →',
        variant: ButtonVariant.primary,
        isLoading: _isSubmitting,
        onPressed: _medicalDisclaimerChecked ? _submitAndNavigate : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoCard(
            bgColor: Colors.white,
            borderColor: AppColors.borderLight,
            iconBg: const Color(0xFFFEF0E6),
            iconWidget: const Text('⚕️', style: TextStyle(fontSize: 12)),
            title: 'Medical disclaimer',
            titleColor: AppColors.nearBlack,
            body: 'Mytr.AI provides personalised guidance to support — not replace — advice from your doctor or endocrinologist. Always consult your healthcare provider before adjusting insulin doses.',
            bodyColor: const Color(0xFF888888),
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            bgColor: const Color(0xFFE8F8FF),
            borderColor: const Color(0xFF9DDBF0),
            iconBg: AppColors.cyan,
            iconWidget: const Icon(LucideIcons.clipboardList, color: Colors.white, size: 12),
            title: 'Helping build India\'s insulin pump',
            titleColor: const Color(0xFF006A8A),
            body: 'We are developing an affordable indigenous insulin pump for India. With your consent, non-sensitive, anonymised usage patterns from this app — such as lifestyle correlations and glucose trends — may be used to improve pump dosing algorithms.',
            bodyColor: const Color(0xFF007AA0),
            footer: '✓ No personal identifiers ever shared\n·  ✓ Fully anonymised  ·  ✓ Opt out anytime',
            footerColor: const Color(0xFF009BBF),
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            bgColor: Colors.white,
            borderColor: AppColors.borderLight,
            iconBg: const Color(0xFFF0FDE4),
            iconWidget: const Text('🔒', style: TextStyle(fontSize: 12)),
            title: 'Your data is yours',
            titleColor: AppColors.nearBlack,
            body: 'All health data is stored securely on Indian servers in compliance with DPDPA 2023. You can export or delete your data at any time from Profile settings.',
            bodyColor: const Color(0xFF888888),
          ),
          
          const SizedBox(height: 32),
          
          _buildCheckboxRow(
            checked: _medicalDisclaimerChecked,
            activeColor: AppColors.nearBlack,
            text: 'I understand Mytr.AI supports but does not replace medical advice.',
            onTap: () => setState(() => _medicalDisclaimerChecked = !_medicalDisclaimerChecked),
          ),
          const SizedBox(height: 16),
          _buildCheckboxRow(
            checked: _researchConsentChecked,
            activeColor: AppColors.cyan,
            text: 'I consent to anonymised usage data being used for insulin pump research.',
            onTap: () => setState(() => _researchConsentChecked = !_researchConsentChecked),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required Color bgColor,
    required Color borderColor,
    required Color iconBg,
    required Widget iconWidget,
    required String title,
    required Color titleColor,
    required String body,
    required Color bodyColor,
    String? footer,
    Color? footerColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(child: iconWidget),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(
              color: bodyColor,
              fontSize: 8.5,
              height: 1.5,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 12),
            Text(
              footer,
              style: TextStyle(
                color: footerColor,
                fontSize: 8,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildCheckboxRow({
    required bool checked,
    required Color activeColor,
    required String text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 2, right: 12),
            decoration: BoxDecoration(
              color: checked ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: checked ? activeColor : AppColors.borderLight,
                width: 1.5,
              ),
            ),
            child: checked
                ? const Center(
                    child: Icon(LucideIcons.check, color: Colors.white, size: 14),
                  )
                : null,
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.nearBlack,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
