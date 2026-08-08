import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../onboarding_provider.dart';
import '../widgets/onboarding_layout.dart';
import '../../../../features/cgm/models/cgm_connection_state.dart';
import '../../../../features/cgm/ui/widgets/cgm_device_picker.dart';
import '../../../../features/cgm/providers/cgm_connection_provider.dart';
import '../../../wearables/providers/wearable_provider.dart';

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingState = ref.watch(onboardingProvider);
    final cgmState        = ref.watch(cgmConnectionProvider);

    final isFitness = onboardingState.userType == UserType.fitness;
    final currentStep = isFitness ? 5 : 6;
    final totalSteps = isFitness ? 7 : 8;

    final cgmConnected = cgmState.status == CgmConnectionStatus.connected;

    return OnboardingLayout(
      currentStep: currentStep + 1,
      eyebrowText: 'STEP ${currentStep + 1} OF $totalSteps · OPTIONAL',
      title: 'Connect your\ndevices',
      subtitle: isFitness 
          ? 'Sync your wearable for activity and sleep data.'
          : 'Skip now — connect from Profile settings anytime',
      bottomCta: Column(
        children: [
          PrimaryButton(
            text: cgmConnected ? 'Continue →' : 'Skip for now →',
            variant: cgmConnected ? ButtonVariant.primary : ButtonVariant.tertiary,
            onPressed: () {
              if (cgmConnected && cgmState.connectedDevice != null) {
                ref.read(onboardingProvider.notifier).setDeviceSetup(
                  DeviceSetup(cgmDevice: cgmState.connectedDevice!.name),
                );
              }
              context.push('/onboarding/acknowledgement');
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // CGM Picker (Hidden for fitness users, except manual entry)
          CgmDevicePicker(
            showCgmDevices: !isFitness,
            showManualEntry: true,
            redirectTo: '/onboarding/acknowledgement',
          ),
          
          const SizedBox(height: 32),

          // ── Fitness & wearables ──────────────────────────────────────
          const _SectionHeader('FITNESS & WEARABLES'),
          const SizedBox(height: 12),
          const _WearablesGrid(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5));
  }
}

// Was purely decorative before this fix — tapping a tile toggled local
// widget state and nothing else, so a user could "select" Apple Health here
// and nothing would actually be connected. Now backed by the same
// wearableProvider that the real connect screen (ManageDevicesScreen,
// reachable at /profile/devices) uses, so tapping has the same real
// effect: a genuine HealthKit/Health Connect permission request, not a
// fake checkmark.
//
// One tile now, not four: Garmin was never implemented (removed rather
// than left as a fake "coming soon" option), and Fitbit is no longer a
// separate connect path — its Android app writes into Health Connect
// directly, and Health Connect itself is a permission grant (OS-level on
// Android 14+), not a second account login. So there's exactly one real
// option per platform.
class _WearablesGrid extends ConsumerStatefulWidget {
  const _WearablesGrid();
  @override
  ConsumerState<_WearablesGrid> createState() => _WearablesGridState();
}

class _WearablesGridState extends ConsumerState<_WearablesGrid> {
  bool _connecting = false;

  @override
  Widget build(BuildContext context) {
    final wearables = ref.watch(wearableProvider).valueOrNull;
    final isConnected = wearables?.healthConnected ?? false;
    final label = wearables?.healthName ??
        (!kIsWeb && Platform.isIOS ? 'Apple Health' : 'Google Health Connect / Fitbit');

    return GestureDetector(
      onTap: _connecting ? null : _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isConnected ? AppColors.nearBlack : AppColors.borderLight, width: isConnected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            const Text('⌚', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.nearBlack, fontSize: 10, fontWeight: FontWeight.bold))),
            if (_connecting)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
            else if (isConnected)
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.limeAccent, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap() async {
    setState(() => _connecting = true);
    try {
      await ref.read(wearableProvider.notifier).connectHealth();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }
}
