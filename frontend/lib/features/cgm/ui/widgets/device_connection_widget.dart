import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../models/cgm_connection_state.dart';
import '../../providers/cgm_connection_provider.dart';
import 'cgm_error_card.dart';
import 'cgm_connected_card.dart';
import 'dexcom_prereq_checklist.dart';

class DeviceConnectionWidget extends ConsumerStatefulWidget {
  final String deviceType;
  final Function(CgmConnectionState)? onConnectionChanged;

  const DeviceConnectionWidget({
    super.key,
    required this.deviceType,
    this.onConnectionChanged,
  });

  @override
  ConsumerState<DeviceConnectionWidget> createState() => _DeviceConnectionWidgetState();
}

class _DeviceConnectionWidgetState extends ConsumerState<DeviceConnectionWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cgmConnectionProvider);

    // Notify parent of changes
    ref.listen(cgmConnectionProvider, (_, next) {
      widget.onConnectionChanged?.call(next);
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.status == CgmConnectionStatus.connected &&
            state.connectedInfo != null &&
            state.connectedInfo!.deviceType.name.toUpperCase().contains(widget.deviceType.split('_')[0])) ...[
          CgmConnectedCard(info: state.connectedInfo!),
        ] else ...[
          _buildPreConnectionUI(state),
        ],

        // Error card
        if (state.status == CgmConnectionStatus.connectionFailed &&
            state.error != null) ...[
          const SizedBox(height: 16),
          CgmErrorCard(
            error: state.error!,
            onRetry: () => _handleConnect(),
          ),
        ],

        const SizedBox(height: 24),
        
        if (state.status != CgmConnectionStatus.connected)
          PrimaryButton(
            text: _getButtonText(),
            variant: ButtonVariant.secondary, // Cyan
            isLoading: state.isLoading,
            onPressed: state.isLoading ? null : () => _handleConnect(),
          ),
      ],
    );
  }

  Widget _buildPreConnectionUI(CgmConnectionState state) {
    if (widget.deviceType.startsWith('DEXCOM')) {
      return const DexcomPrereqChecklist();
    } else if (widget.deviceType.startsWith('LIBRE')) {
      return _buildLibreForm();
    }
    return const SizedBox.shrink();
  }

  Widget _buildLibreForm() {
    // Simplified form for Libre credentials
    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            labelText: 'LibreLinkUp Email',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Password',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  String _getButtonText() {
    if (widget.deviceType.startsWith('DEXCOM')) {
      return 'Connect with Dexcom →';
    } else if (widget.deviceType.startsWith('LIBRE')) {
      return 'Verify Credentials →';
    } else if (widget.deviceType == 'MANUAL') {
      return 'Set up Manual Entry';
    }
    return 'Connect Device';
  }

  void _handleConnect() {
    final notifier = ref.read(cgmConnectionProvider.notifier);
    if (widget.deviceType.startsWith('DEXCOM')) {
      notifier.connectDexcom();
    } else if (widget.deviceType.startsWith('LIBRE')) {
      // In a real app, we'd pass email/password from the form
      notifier.connectLibre('user@example.com', 'password123');
    } else if (widget.deviceType == 'MANUAL') {
      notifier.setManualEntry();
    }
  }
}
