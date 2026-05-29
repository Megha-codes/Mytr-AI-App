import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';

class WearableConnectionTile extends StatelessWidget {
  final String name;
  final String description;
  final IconData icon;
  final bool isConnected;
  final DateTime? lastSync;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const WearableConnectionTile({
    super.key,
    required this.name,
    required this.description,
    required this.icon,
    required this.isConnected,
    this.lastSync,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: isConnected ? AppColors.cyan : AppColors.textSecondary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.nearBlack,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (isConnected && lastSync != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Last sync: ${_formatDate(lastSync!)}',
                      style: const TextStyle(
                        color: AppColors.cyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (isConnected) {
      return TextButton(
        onPressed: onDisconnect,
        child: const Text(
          'Disconnect',
          style: TextStyle(
            color: AppColors.error,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else {
      return ElevatedButton(
        onPressed: onConnect,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cyan,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        child: const Text(
          'Connect',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
    }
  }

  String _formatDate(DateTime dt) {
    // Simple formatter
    return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
