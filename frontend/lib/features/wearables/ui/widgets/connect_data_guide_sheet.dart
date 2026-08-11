import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/health/metric_copy.dart';
import '../../providers/wearable_provider.dart';

/// The "Connect your data" guidance flow (Phase-1 polish): opened from any
/// empty health-metric card's tap-through, or as a generic entry point.
/// Two concrete steps — (a) grant the OS-level Health Connect/Apple Health
/// permission, (b) connect a CGM or use manual entry — plus the single
/// most-missed step from docs/health-data-setup.md §4: granting
/// permission alone does nothing if the wearable's own companion app
/// (Fitbit, Samsung Health, ...) isn't separately set to sync into Health
/// Connect. That gap is exactly what makes "I connected but see nothing"
/// confusing, so it's surfaced here unconditionally, not just on failure.
///
/// [highlightMetric] optionally explains why THIS specific card is empty —
/// omit it for a generic entry point (e.g. the activity screen's bottom
/// connect prompt, which isn't about any one metric).
void showConnectDataGuide(BuildContext context, {MetricInfo? highlightMetric}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ConnectDataGuideSheet(
      outerContext: context,
      highlightMetric: highlightMetric,
    ),
  );
}

class _ConnectDataGuideSheet extends ConsumerWidget {
  final BuildContext outerContext;
  final MetricInfo? highlightMetric;

  const _ConnectDataGuideSheet({required this.outerContext, this.highlightMetric});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wearable = ref.watch(wearableProvider).valueOrNull;
    final isConnected = wearable?.healthConnected ?? false;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: const BoxDecoration(
          color: AppTheme.backgroundWhite,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connect your data', style: AppTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'A couple of steps get your real health and glucose data flowing in.',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),

            if (highlightMetric != null) ...[
              const SizedBox(height: 20),
              _Callout(
                icon: LucideIcons.info,
                color: AppTheme.accentCyan,
                text: '${highlightMetric!.label}: ${highlightMetric!.emptyMessage}',
              ),
            ],

            const SizedBox(height: 24),
            _Step(
              number: '1',
              title: 'Grant Health permission',
              description: isConnected
                  ? 'Connected — your phone can read step and health data.'
                  : 'Lets Mytr.AI read steps, heart rate, sleep, and HRV from '
                      'Health Connect / Apple Health.',
              actionLabel: isConnected ? null : 'Grant permission',
              onAction: isConnected ? null : () => _connectHealth(context, ref),
            ),

            const SizedBox(height: 16),
            _Callout(
              icon: LucideIcons.alertTriangle,
              color: AppTheme.accentOrange,
              text: "Already connected but still seeing nothing? Open your watch's "
                  'own app (Fitbit, Samsung Health, etc.) → Settings → Health '
                  'Connect, and make sure syncing is turned on. This is the step '
                  'people miss most.',
            ),

            const SizedBox(height: 16),
            _Step(
              number: '2',
              title: 'Connect a CGM, or log manually',
              description: 'Pair a Libre sensor, or track glucose yourself from Manage Devices.',
              actionLabel: 'Manage devices',
              onAction: () {
                Navigator.of(context).pop();
                if (outerContext.mounted) outerContext.push('/profile/devices');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectHealth(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(wearableProvider.notifier).connectHealth();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.glucoseHyper),
        );
      }
    }
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Step({
    required this.number,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppTheme.brandGreenLight, shape: BoxShape.circle),
          child: Text(
            number,
            style: AppTheme.labelLarge.copyWith(color: AppTheme.brandGreenDark, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.labelLarge.copyWith(color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(description, style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary)),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Callout({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
