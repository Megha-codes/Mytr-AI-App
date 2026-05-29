import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../models/cgm_connection_state.dart';
import '../../providers/cgm_connection_provider.dart';
import '../../../../features/onboarding/onboarding_provider.dart';

class ManualConnectScreen extends ConsumerWidget {
  final String redirectTo;

  const ManualConnectScreen({
    super.key,
    this.redirectTo = '/onboarding/acknowledgement',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cgmConnectionProvider);

    // Navigate away when connection succeeds
    ref.listen(cgmConnectionProvider, (_, next) {
      if (next.status == CgmConnectionStatus.connected && context.mounted) {
        context.go(redirectTo);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Dark header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (context.canPop())
                    GestureDetector(
                      onTap: () {
                        ref.read(cgmConnectionProvider.notifier).reset();
                        context.pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Icon(LucideIcons.arrowLeft, 
                            color: Colors.white, size: 22),
                      ),
                    ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDE4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text('✏️', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'GLUCOMETER / MANUAL',
                    style: TextStyle(
                      color: AppColors.limeAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Manual Entry\nMode',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Log readings from any device manually. All metabolic insights remain available.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 9,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // ── Cream body ───────────────────────────────────────────────
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _ManualInfoCard(
                        icon: LucideIcons.plusCircle,
                        title: 'How it works',
                        text: 'You will enter your blood glucose readings manually in the app. Just tap the + button on the dashboard to log a reading at any time.',
                      ),
                      const SizedBox(height: 12),
                      const _ManualInfoCard(
                        icon: LucideIcons.clock,
                        title: 'Post-Meal Tracking',
                        text: 'To track outcomes, the app will prompt you to log readings at 1 hour and 2 hours after meals.',
                      ),
                      const SizedBox(height: 12),
                      const _ManualInfoCard(
                        icon: LucideIcons.zap,
                        title: 'All Features Available',
                        text: 'Insights, meal scores, and health reports work perfectly. Only real-time live streaming is disabled.',
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),

            // ── Bottom CTA ───────────────────────────────────────────────
            SafeArea(
              top: false,
              child: Container(
                color: AppColors.cream,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    PrimaryButton(
                      text: 'Set up manual entry →',
                      variant: ButtonVariant.primary,
                      isLoading: state.isLoading,
                      onPressed: state.isLoading 
                        ? null 
                        : () {
                            if (redirectTo.startsWith('/onboarding')) {
                              ref.read(onboardingProvider.notifier).setDeviceSetup(
                                DeviceSetup(cgmDevice: 'MANUAL', manualEntry: true),
                              );
                              context.go(redirectTo);
                            } else {
                              ref.read(cgmConnectionProvider.notifier).setManualEntry();
                            }
                          },
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () {
                        ref.read(cgmConnectionProvider.notifier).reset();
                        context.pop();
                      },
                      child: const Text(
                        'Choose a different device',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
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

class _ManualInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _ManualInfoCard({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.limeAccent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.nearBlack,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
