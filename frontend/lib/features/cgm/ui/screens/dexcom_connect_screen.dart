import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../models/cgm_connection_state.dart';
import '../../providers/cgm_connection_provider.dart';
import '../widgets/dexcom_prereq_checklist.dart';
import '../widgets/cgm_error_card.dart';
import '../widgets/cgm_connected_card.dart';

class DexcomConnectScreen extends ConsumerWidget {
  /// When [redirectTo] is set, navigates there on success.
  /// Used by both onboarding and post-onboarding reconnection flows.
  final String redirectTo;

  const DexcomConnectScreen({
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
                      color: AppColors.cyan,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(LucideIcons.target, 
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'CONTINUOUS GLUCOSE MONITOR',
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Connect Dexcom\nG6 / G7',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We use Dexcom\'s secure login — Mytr.AI never sees your Dexcom password.',
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
                      // Show connected card if already connected
                      if (state.status == CgmConnectionStatus.connected &&
                          state.connectedInfo != null) ...[
                        CgmConnectedCard(info: state.connectedInfo!),
                      ] else ...[
                        const DexcomPrereqChecklist(),
                        const SizedBox(height: 16),
                        const _SecurityBadgeRow(),
                      ],

                      // Error card
                      if (state.status == CgmConnectionStatus.connectionFailed &&
                          state.error != null) ...[
                        const SizedBox(height: 16),
                        CgmErrorCard(
                          error: state.error!,
                          onRetry: () => ref
                              .read(cgmConnectionProvider.notifier)
                              .connectDexcom(),
                        ),
                        if (state.error == CgmConnectError.dexcomShareNotEnabled) ...[
                          const SizedBox(height: 12),
                          PrimaryButton(
                            text: 'Open Dexcom App',
                            variant: ButtonVariant.tertiary,
                            onPressed: () => _openDexcomApp(),
                          ),
                        ],
                      ],

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),

            // ── Bottom CTA (always pinned) ───────────────────────────────
            SafeArea(
              top: false,
              child: Container(
                color: AppColors.cream,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    PrimaryButton(
                      text: 'Connect with Dexcom →',
                      variant: ButtonVariant.secondary, // Cyan
                      isLoading: state.isLoading,
                      onPressed: state.isLoading
                          ? null
                          : () => ref
                              .read(cgmConnectionProvider.notifier)
                              .connectDexcom(),
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

  Future<void> _openDexcomApp() async {
    final uri = Uri.parse('dexcomapp://');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

class _SecurityBadgeRow extends StatelessWidget {
  const _SecurityBadgeRow();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: const [
        _SecurityBadge(icon: LucideIcons.shield, label: 'No password\nshared'),
        _SecurityBadge(icon: LucideIcons.lock, label: 'TLS\nencrypted'),
        _SecurityBadge(icon: LucideIcons.xCircle, label: 'Disconnect\nanytime'),
      ],
    );
  }
}

class _SecurityBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SecurityBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F8FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Icon(icon, color: AppColors.cyan, size: 16),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 7.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
