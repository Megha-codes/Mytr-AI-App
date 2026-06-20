import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../cgm/ui/widgets/device_connection_widget.dart';
import '../../../wearables/ui/widgets/wearable_connection_tile.dart';
import '../../../wearables/providers/wearable_provider.dart';

class ManageDevicesScreen extends ConsumerWidget {
  const ManageDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wearableAsync = ref.watch(wearableProvider);

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
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
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle('GLUCOSE MONITOR'),
                      const SizedBox(height: 16),
                      const DeviceConnectionWidget(deviceType: 'LIBRE'),
                      const SizedBox(height: 32),
                      _buildSectionTitle('WEARABLES'),
                      const SizedBox(height: 16),
                      wearableAsync.when(
                        data: (state) => _buildWearablesList(context, ref, state),
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        error: (_, __) => _buildWearablesList(
                          context, ref, const WearableConnectionState(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 8),
          const Text(
            'Manage Devices',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.cyan,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildWearablesList(
    BuildContext context,
    WidgetRef ref,
    WearableConnectionState state,
  ) {
    final isIOS = !kIsWeb && Platform.isIOS;
    final isAndroid = !kIsWeb && Platform.isAndroid;

    return Column(
      children: [
        // Apple Health — iOS only
        if (isIOS || kIsWeb)
          WearableConnectionTile(
            name: 'Apple Health',
            description: 'Steps, heart rate, and sleep data.',
            icon: LucideIcons.heart,
            isConnected: state.healthConnected,
            lastSync: state.healthLastSync,
            onConnect: () => _connectHealth(context, ref),
            onDisconnect: () => _showDisconnectSheet(
              context,
              ref,
              name: 'Apple Health',
              onConfirm: () => ref.read(wearableProvider.notifier).disconnectHealth(),
            ),
          ),

        // Health Connect — Android only (replaced Google Fit in 2024)
        if (isAndroid || kIsWeb)
          WearableConnectionTile(
            name: 'Health Connect',
            description: 'Activity and fitness tracking via Android Health Connect.',
            icon: LucideIcons.activity,
            isConnected: state.healthConnected,
            lastSync: state.healthLastSync,
            onConnect: () => _connectHealth(context, ref),
            onDisconnect: () => _showDisconnectSheet(
              context,
              ref,
              name: 'Google Fit',
              onConfirm: () => ref.read(wearableProvider.notifier).disconnectHealth(),
            ),
          ),

        // Fitbit via Google Health API
        WearableConnectionTile(
          name: 'Fitbit',
          description: 'Sync Fitbit device data via Google Health API.',
          icon: LucideIcons.watch,
          isConnected: state.googleHealthConnected,
          lastSync: state.googleHealthLastSync,
          onConnect: () => _connectGoogleHealth(context, ref),
          onDisconnect: () => _showDisconnectSheet(
            context,
            ref,
            name: 'Fitbit',
            onConfirm: () =>
                ref.read(wearableProvider.notifier).disconnectGoogleHealth(),
          ),
        ),

        // Garmin — placeholder (no integration yet)
        WearableConnectionTile(
          name: 'Garmin Connect',
          description: 'Coming soon.',
          icon: LucideIcons.award,
          isConnected: false,
          onConnect: () => _showComingSoon(context, 'Garmin Connect'),
          onDisconnect: () {},
        ),
      ],
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _connectHealth(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(wearableProvider.notifier).connectHealth();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _connectGoogleHealth(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(wearableProvider.notifier).connectGoogleHealth();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showComingSoon(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name integration coming soon')),
    );
  }

  void _showDisconnectSheet(
    BuildContext context,
    WidgetRef ref, {
    required String name,
    required VoidCallback onConfirm,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.alertTriangle, color: AppColors.error),
            ),
            const SizedBox(height: 20),
            Text(
              'Disconnect $name?',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.nearBlack,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You will stop receiving live data from $name until you reconnect.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              text: 'Disconnect',
              variant: ButtonVariant.primary,
              onPressed: () {
                onConfirm();
                ctx.pop();
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ctx.pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
