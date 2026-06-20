import 'package:flutter/material.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../models/cgm_connection_state.dart';

class CgmErrorCard extends StatelessWidget {
  final CgmConnectError error;
  final VoidCallback? onRetry;

  const CgmErrorCard({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFEE2E2), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.alertCircle, color: Color(0xFFEF4444), size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connection Failed',
                      style: TextStyle(color: Color(0xFF991B1B), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      error.userMessage,
                      style: const TextStyle(color: Color(0xFF991B1B), fontSize: 9, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
