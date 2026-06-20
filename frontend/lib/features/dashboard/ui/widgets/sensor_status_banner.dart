import 'package:flutter/material.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';

class SensorStatusBanner extends StatelessWidget {
  final String status; // 'EXPIRED', 'WARNING_CRITICAL', 'WARNING_LOW'
  final VoidCallback onTap;

  const SensorStatusBanner({
    super.key,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (status == 'ACTIVE' || status == 'IDLE') return const SizedBox.shrink();

    final isExpired = status == 'EXPIRED';
    final isCritical = status == 'WARNING_CRITICAL';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isExpired ? AppColors.error : (isCritical ? Colors.orange : AppColors.cyan),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isExpired ? LucideIcons.xCircle : LucideIcons.alertTriangle,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTitle(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    _getMessage(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  String _getTitle() {
    switch (status) {
      case 'EXPIRED':
        return 'SENSOR EXPIRED';
      case 'WARNING_CRITICAL':
        return 'REPLACE SENSOR SOON';
      case 'WARNING_LOW':
        return 'SENSOR EXPIRING';
      default:
        return 'CHECK SENSOR';
    }
  }

  String _getMessage() {
    switch (status) {
      case 'EXPIRED':
        return 'Glucose data unavailable. Tap to reconnect.';
      case 'WARNING_CRITICAL':
        return 'Less than 2 hours remaining. Tap for info.';
      case 'WARNING_LOW':
        return 'Less than 24 hours remaining. Prepare a spare.';
      default:
        return 'Tap for sensor management.';
    }
  }
}
