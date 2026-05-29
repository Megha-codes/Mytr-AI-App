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

class _WearablesGrid extends StatefulWidget {
  const _WearablesGrid();
  @override
  State<_WearablesGrid> createState() => _WearablesGridState();
}

class _WearablesGridState extends State<_WearablesGrid> {
  final Set<String> _selected = {};
  static const _items = [
    ('Apple Health', '⌚'),
    ('Google Fit',   '📱'),
    ('Fitbit',        '🟠'),
    ('Garmin',        '🟢'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.2,
      children: _items.map<Widget>((item) {
        final isSelected = _selected.contains(item.$1);
        return GestureDetector(
          onTap: () => setState(() => isSelected ? _selected.remove(item.$1) : _selected.add(item.$1)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? AppColors.nearBlack : AppColors.borderLight, width: isSelected ? 1.5 : 1),
            ),
            child: Row(
              children: [
                Text(item.$2, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(child: Text(item.$1, style: const TextStyle(color: AppColors.nearBlack, fontSize: 8, fontWeight: FontWeight.bold))),
                if (isSelected) Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.limeAccent, shape: BoxShape.circle)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
