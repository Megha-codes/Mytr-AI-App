import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../models/cgm_device_type.dart';
import '../../models/cgm_connected_info.dart';
import '../../providers/cgm_connection_provider.dart';

class CgmConnectedCard extends ConsumerWidget {
  final CgmConnectedInfo info;

  const CgmConnectedCard({super.key, required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManual = info.deviceType == CgmDeviceType.manual;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.limeAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.limeAccent.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header Row ────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.limeAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.check, color: AppColors.limeAccent, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isManual ? 'Manual entry set up' : 'Connected — ${info.deviceType.displayName}',
                  style: const TextStyle(
                    color: AppColors.nearBlack,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Data Section ──────────────────────────────────────────────
          if (isManual)
            const Text(
              'Log your first reading from the dashboard.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            )
          else ...[
            // Last reading and Trend
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last reading: ${info.lastReadingMgdl?.toString() ?? '--'} mg/dL — ${_timeAgo(info.lastReadingTime ?? DateTime.now())}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Trend: ',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          _TrendArrow(trend: info.trend),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),

            // Sensor Expiry
            if (info.expiryDaysRemaining != null)
              Text(
                info.expiryDaysRemaining! < 2 
                    ? 'Sensor: Replace sensor soon' 
                    : 'Sensor: ${info.expiryDaysRemaining} days remaining',
                style: TextStyle(
                  color: info.expiryDaysRemaining! < 2 ? AppColors.error : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: info.expiryDaysRemaining! < 2 ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
          ],

          // ── Warning for Expired/No Sensor ────────────────────────────
          if (info.isExpired || info.noSensor) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB), // Amber-50
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFEF3C7)), // Amber-100
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.alertTriangle, color: Color(0xFFD97706), size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No active sensor',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Start a new sensor session to begin live tracking.',
                          style: TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // ── Footer ────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isManual)
                TextButton(
                  onPressed: () {
                    // This would trigger the picker/onboarding flow again
                  },
                  child: const Text(
                    'Change to CGM',
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: () => _showDisconnectSheet(context, ref, info.deviceType.displayName),
                  child: const Text(
                    'Disconnect',
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  void _showDisconnectSheet(BuildContext context, WidgetRef ref, String deviceName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Disconnect Device?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.nearBlack),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to disconnect $deviceName? You will stop receiving live glucose data until you reconnect.',
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                text: 'Disconnect',
                variant: ButtonVariant.tertiary,
                onPressed: () {
                  ref.read(cgmConnectionProvider.notifier).disconnect();
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendArrow extends StatelessWidget {
  final String? trend;
  const _TrendArrow({this.trend});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String label;

    switch (trend?.toUpperCase()) {
      case 'RISING_FAST':
        icon = LucideIcons.chevronsUp; color = const Color(0xFFEF4444); label = 'Rising fast';
        break;
      case 'RISING':
        icon = LucideIcons.chevronUp; color = AppColors.vividOrange; label = 'Rising';
        break;
      case 'STABLE':
        icon = LucideIcons.arrowRight; color = AppColors.limeAccent; label = 'Stable';
        break;
      case 'FALLING':
        icon = LucideIcons.chevronDown; color = AppColors.vividOrange; label = 'Falling';
        break;
      case 'FALLING_FAST':
        icon = LucideIcons.chevronsDown; color = const Color(0xFFEF4444); label = 'Falling fast';
        break;
      default:
        icon = LucideIcons.minus; color = AppColors.textSecondary; label = '--';
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
