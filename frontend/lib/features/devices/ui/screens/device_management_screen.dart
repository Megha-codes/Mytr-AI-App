import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../core/widgets/state_feedback_widgets.dart';
import '../../models/paired_device.dart';
import '../../providers/device_list_provider.dart';

/// Lists paired desk devices (architecture-v3.md §2.2) with rename/unpair,
/// and the entry point to pair a new one.
class DeviceManagementScreen extends ConsumerWidget {
  const DeviceManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(deviceListProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      appBar: AppBar(
        title: const Text('Desk Display'),
        backgroundColor: AppTheme.backgroundCream,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(deviceListProvider.notifier).refresh(),
        child: devicesAsync.when(
          data: (devices) => _DeviceList(devices: devices),
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppTheme.screenPadding),
            children: const [CardShimmer(height: 100), SizedBox(height: 12), CardShimmer(height: 100)],
          ),
          error: (e, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppTheme.screenPadding),
            children: [
              InlineErrorCard(
                message: 'Could not load your devices.',
                onRetry: () => ref.read(deviceListProvider.notifier).refresh(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/profile/desk-device/pair'),
        backgroundColor: AppTheme.brandGreen,
        icon: const Icon(LucideIcons.plusCircle, color: Colors.white),
        label: const Text('Pair device', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices});

  final List<PairedDevice> devices;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTheme.screenPadding),
        children: [
          ContextualEmptyState(
            icon: Icons.dvr_outlined,
            message: 'No desk devices paired yet. Pair one to see live glucose without opening the app.',
            actionLabel: 'Pair a device',
            onAction: () => context.push('/profile/desk-device/pair'),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding, AppTheme.screenPadding, AppTheme.screenPadding, 96,
      ),
      itemCount: devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _DeviceCard(device: devices[index]),
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.device});

  final PairedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.brandGreenLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.dvr_outlined, color: AppTheme.brandGreen),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.displayName, style: AppTheme.bodyLarge),
                const SizedBox(height: 4),
                Text(_lastSeenLabel(device.lastSeenAt), style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.textSecondary),
            onPressed: () => _showRenameDialog(context, ref, device),
            tooltip: 'Rename',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.glucoseLow),
            onPressed: () => _showUnpairDialog(context, ref, device),
            tooltip: 'Unpair',
          ),
        ],
      ),
    );
  }

  String _lastSeenLabel(DateTime? lastSeenAt) {
    if (lastSeenAt == null) return 'Never connected';
    final minutes = DateTime.now().difference(lastSeenAt).inMinutes;
    if (minutes < 1) return 'Active now';
    if (minutes < 60) return 'Last seen $minutes min ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return 'Last seen ${hours}h ago';
    return 'Last seen ${hours ~/ 24}d ago';
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref, PairedDevice device) async {
    final controller = TextEditingController(text: device.name ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Bedside'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || !context.mounted) return;
    final error = await ref.read(deviceListProvider.notifier).rename(device.deviceId, newName);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppTheme.glucoseLow),
      );
    }
  }

  Future<void> _showUnpairDialog(BuildContext context, WidgetRef ref, PairedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair this device?'),
        content: Text('${device.displayName} will need to be paired again before it can show live data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unpair', style: TextStyle(color: AppTheme.glucoseLow)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final error = await ref.read(deviceListProvider.notifier).unpair(device.deviceId);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppTheme.glucoseLow),
      );
    }
  }
}
