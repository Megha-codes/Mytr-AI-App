import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../cgm/ui/widgets/device_connection_widget.dart';
import '../../../../features/wearables/ui/widgets/wearable_connection_tile.dart';

class ManageDevicesScreen extends ConsumerWidget {
  const ManageDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      // Using the reusable widget
                      const DeviceConnectionWidget(deviceType: 'LIBRE'),
                      
                      const SizedBox(height: 32),
                      _buildSectionTitle('WEARABLES'),
                      const SizedBox(height: 16),
                      _buildWearablesList(context),
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

  Widget _buildWearablesList(BuildContext context) {
    final isIOS = !kIsWeb && Platform.isIOS;
    final isAndroid = !kIsWeb && Platform.isAndroid;

    return Column(
      children: [
        if (isIOS || kIsWeb)
          WearableConnectionTile(
            name: 'Apple Health',
            description: 'Steps, heart rate, and sleep data.',
            icon: LucideIcons.heart,
            isConnected: false,
            onConnect: () => _handleConnect('APPLE_HEALTH'),
            onDisconnect: () => _showDisconnectConfirmation(context, 'Apple Health'),
          ),
        if (isAndroid || kIsWeb)
          WearableConnectionTile(
            name: 'Google Fit',
            description: 'Activity and fitness tracking.',
            icon: LucideIcons.activity,
            isConnected: false,
            onConnect: () => _handleConnect('GOOGLE_FIT'),
            onDisconnect: () => _showDisconnectConfirmation(context, 'Google Fit'),
          ),
        WearableConnectionTile(
          name: 'Fitbit',
          description: 'Comprehensive health monitoring.',
          icon: LucideIcons.watch,
          isConnected: true,
          lastSync: DateTime.now().subtract(const Duration(minutes: 12)),
          onConnect: () => _handleConnect('FITBIT'),
          onDisconnect: () => _showDisconnectConfirmation(context, 'Fitbit'),
        ),
        WearableConnectionTile(
          name: 'Garmin Connect',
          description: 'High-performance athletic data.',
          icon: LucideIcons.award,
          isConnected: false,
          onConnect: () => _handleConnect('GARMIN'),
          onDisconnect: () => _showDisconnectConfirmation(context, 'Garmin'),
        ),
      ],
    );
  }

  void _handleConnect(String type) {
    // Implement connection logic
  }

  void _showDisconnectConfirmation(BuildContext context, String device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
              'Disconnect $device?',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.nearBlack,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You will stop receiving live data from $device until you reconnect.',
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
                // Perform DELETE call
                context.pop();
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.pop(),
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
