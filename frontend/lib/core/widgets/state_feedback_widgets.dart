import 'package:flutter/material.dart';
import '../icons/lucide_icons.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';

class InlineErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const InlineErrorCard({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      backgroundColor: AppTheme.glucoseHypo.withValues(alpha: 0.05),
      borderColor: AppTheme.glucoseHypo.withValues(alpha: 0.2),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle, color: AppTheme.glucoseHypo, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.glucoseHypo),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class ContextualEmptyState extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData icon;

  const ContextualEmptyState({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.icon = LucideIcons.layers,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(icon, size: 40, color: AppTheme.textHint),
              const SizedBox(height: 16),
              Text(message, style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel, style: const TextStyle(color: AppTheme.brandGreen)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
