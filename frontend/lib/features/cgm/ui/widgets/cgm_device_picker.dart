import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';
import '../../models/cgm_connection_state.dart';
import '../../providers/cgm_connection_provider.dart';
import 'cgm_connected_card.dart';
import 'cgm_error_card.dart';

/// Self-contained CGM device picker.
class CgmDevicePicker extends ConsumerStatefulWidget {
  final bool showCgmDevices;
  final bool showManualEntry;
  final String redirectTo;

  const CgmDevicePicker({
    super.key,
    this.showCgmDevices = true,
    this.showManualEntry = true,
    this.redirectTo = '/onboarding/acknowledgement',
  });

  @override
  ConsumerState<CgmDevicePicker> createState() => _CgmDevicePickerState();
}

class _CgmDevicePickerState extends ConsumerState<CgmDevicePicker> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cgmConnectionProvider);

    if (state.status == CgmConnectionStatus.connected && state.connectedInfo != null) {
      return CgmConnectedCard(info: state.connectedInfo!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.status == CgmConnectionStatus.connectionFailed && state.error != null) ...[
          CgmErrorCard(error: state.error!, onRetry: () => ref.read(cgmConnectionProvider.notifier).reset()),
          const SizedBox(height: 16),
        ],

        if (widget.showCgmDevices) ...[
          _SectionHeader('CONTINUOUS GLUCOSE MONITORS'),
          const SizedBox(height: 12),
          _DeviceRow(
            id: 'dexcom',
            isSelected: _selectedId == 'dexcom',
            iconBg: AppColors.cyan,
            iconWidget: const Icon(LucideIcons.target, color: Colors.white, size: 16),
            title: 'Dexcom G6 / G7',
            subtitle: 'OAuth — Most Secure',
            isLoading: state.status == CgmConnectionStatus.connecting && _selectedId == 'dexcom',
            onTap: () {
              setState(() => _selectedId = 'dexcom');
              context.push('/cgm/dexcom-connect', extra: widget.redirectTo);
            },
          ),
          const SizedBox(height: 8),
          _DeviceRow(
            id: 'libre',
            isSelected: _selectedId == 'libre',
            iconBg: const Color(0xFFE8F8FF),
            iconWidget: const Icon(LucideIcons.smartphone, color: AppColors.cyan, size: 16),
            title: 'FreeStyle Libre 2 / 3',
            subtitle: 'LibreLinkUp credentials',
            isLoading: state.status == CgmConnectionStatus.connecting && _selectedId == 'libre',
            onTap: () {
              setState(() => _selectedId = 'libre');
              context.push('/cgm/libre-connect', extra: widget.redirectTo);
            },
          ),
        ],

        if (widget.showManualEntry) ...[
          const SizedBox(height: 24),
          _SectionHeader('GLUCOMETER / MANUAL'),
          const SizedBox(height: 12),
          _DeviceRow(
            id: 'manual',
            isSelected: _selectedId == 'manual',
            iconBg: const Color(0xFFF0FDE4),
            iconWidget: const Text('✏️', style: TextStyle(fontSize: 14)),
            title: 'Manual entry',
            subtitle: 'Log readings from any glucometer',
            isLoading: state.status == CgmConnectionStatus.connecting && _selectedId == 'manual',
            onTap: () {
              setState(() => _selectedId = 'manual');
              context.push('/cgm/manual-connect', extra: widget.redirectTo);
            },
          ),
        ],
      ],
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

class _DeviceRow extends StatelessWidget {
  final String id;
  final bool isSelected;
  final Color iconBg;
  final Widget iconWidget;
  final String title;
  final String subtitle;
  final bool isLoading;
  final VoidCallback onTap;

  const _DeviceRow({
    required this.id,
    required this.isSelected,
    required this.iconBg,
    required this.iconWidget,
    required this.title,
    required this.subtitle,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? AppColors.limeAccent : AppColors.borderLight, width: isSelected ? 2 : 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
              child: Center(child: iconWidget),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.nearBlack, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 7.5)),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.limeAccent))
            else
              Icon(LucideIcons.chevronRight, color: AppColors.textSecondary.withValues(alpha: 0.5), size: 16),
          ],
        ),
      ),
    );
  }
}
