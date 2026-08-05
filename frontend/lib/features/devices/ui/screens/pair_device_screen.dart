import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../providers/device_list_provider.dart';
import '../../providers/device_pairing_provider.dart';

/// Where a user enters the 8-character code shown on the desk device's
/// screen (architecture-v3.md §2.2) to claim it via POST /devices/pair.
class PairDeviceScreen extends ConsumerStatefulWidget {
  const PairDeviceScreen({super.key});

  @override
  ConsumerState<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends ConsumerState<PairDeviceScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(devicePairingProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      appBar: AppBar(
        title: const Text('Pair a Device'),
        backgroundColor: AppTheme.backgroundCream,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the pairing code shown on your desk display\'s screen.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            _LabeledField(
              label: 'Pairing code',
              controller: _codeController,
              hintText: 'K7M2-QP94',
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            _LabeledField(
              label: 'Name this device (optional)',
              controller: _nameController,
              hintText: 'Bedside',
            ),
            if (state.error != null) ...[
              const SizedBox(height: 16),
              Text(
                state.error!,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.glucoseLow),
              ),
            ],
            const SizedBox(height: 32),
            PrimaryButton(
              text: 'Pair device',
              isLoading: state.isLoading,
              onPressed: state.isLoading ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    final result = await ref.read(devicePairingProvider.notifier).claim(
          code: code,
          name: _nameController.text,
        );

    if (!mounted) return;
    if (result.success) {
      ref.invalidate(deviceListProvider);
      Navigator.pop(context);
    }
    // On failure the error is already shown reactively via state.error.
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.labelSmall),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.backgroundSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: TextField(
            controller: controller,
            textCapitalization: textCapitalization,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textHint),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
