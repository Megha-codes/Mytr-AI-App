import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/dark_header.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/stat_widgets.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../core/widgets/state_feedback_widgets.dart';
import '../../providers/providers.dart';
import '../widgets/glucose_widgets.dart';
import '../widgets/manual_glucose_entry_sheet.dart';

class GlucoseScreen extends ConsumerWidget {
  const GlucoseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cgmAsync = ref.watch(cgmProvider);
    final insulin = ref.watch(insulinProvider);
    final nutritionAsync = ref.watch(nutritionProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(cgmProvider);
          ref.invalidate(nutritionProvider);
          await ref.read(cgmProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: cgmAsync.when(
            data: (cgm) => nutritionAsync.when(
              data: (nutrition) => _buildContent(context, ref, cgm, insulin, nutrition),
              loading: () => const CardShimmer(height: 400),
              error: (e, _) => InlineErrorCard(message: 'Load error', onRetry: () => ref.invalidate(nutritionProvider)),
            ),
            loading: () => const Column(
              children: [
                CardShimmer(height: 300),
                CardShimmer(height: 100),
                CardShimmer(height: 400),
              ],
            ),
            error: (e, _) => Center(
              child: InlineErrorCard(
                message: e.toString(),
                onRetry: () => ref.invalidate(cgmProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openManualEntry(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ManualGlucoseEntrySheet(),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, CGMState cgm, InsulinState insulin, NutritionState nutrition) {
    // Calculated eA1C: (Avg + 46.7) / 28.7
    final estimatedA1C = (cgm.averageGlucose28Days + 46.7) / 28.7;

    return Column(
      children: [
        // ── Zone 1: Dark Header ──────────────────────────────────────────
        DarkHeader(
          title: 'Live Glucose',
          trailing: TagPill(
            label: _getStatusLabel(cgm.currentStatus),
            backgroundColor: _getStatusColor(cgm.currentStatus).withValues(alpha: 0.2),
            textColor: _getStatusColor(cgm.currentStatus),
          ),
          bottomContent: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current reading', style: AppTheme.labelSmall.copyWith(color: AppTheme.textOnDarkMuted)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${cgm.currentGlucose}', style: AppTheme.displayLarge.copyWith(color: Colors.white, fontSize: 56)),
                  const SizedBox(width: 8),
                  Text(cgm.trendArrow, style: AppTheme.displayMedium.copyWith(color: _getStatusColor(cgm.currentStatus))),
                  const SizedBox(width: 8),
                  Text('mg/dL', style: AppTheme.bodySmall.copyWith(color: AppTheme.textOnDarkMuted)),
                ],
              ),
              const SizedBox(height: 24),
              GlucoseZoneLegend(
                currentGlucose: cgm.currentGlucose,
                targetMin: 70, // Mocked range
                targetMax: 180,
              ),
            ],
          ),
        ),

        // ── Zone 2: Stats Strip ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          color: AppTheme.brandGreen,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStripStat('TIME IN RANGE', '${cgm.timeInRange24h.toInt()}%'),
              _buildStripStat('EST. A1C', '${estimatedA1C.toStringAsFixed(1)}%'),
              _buildStripStat('LAST BOLUS', '${insulin.lastBolusAmount}u'),
            ],
          ),
        ),

        // ── Zone 3: Body ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(AppTheme.screenPadding),
          child: Column(
            children: [
              // 24h Path Chart
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('24h path', style: AppTheme.titleLarge),
                        GestureDetector(
                          onTap: () => context.push('/glucose/detail'),
                          child: Text('Tap to expand', style: AppTheme.labelSmall.copyWith(color: AppTheme.accentCyan)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    GlucoseChart24h(
                      data: cgm.last24Hours,
                      mealTimes: nutrition.todaysMeals.map((LoggedMeal m) => m.timestamp).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('12AM', style: AppTheme.labelSmall.copyWith(fontSize: 8)),
                        Text('6AM', style: AppTheme.labelSmall.copyWith(fontSize: 8)),
                        Text('12PM', style: AppTheme.labelSmall.copyWith(fontSize: 8)),
                        Text('6PM', style: AppTheme.labelSmall.copyWith(fontSize: 8)),
                        Text('NOW', style: AppTheme.labelSmall.copyWith(fontSize: 8, color: AppTheme.accentCyan)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // TIR Breakdown
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Time in range breakdown', style: AppTheme.titleLarge),
                    const SizedBox(height: 24),
                    TIRStackedBar(breakdown: cgm.timeInRangeBreakdown),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Glucose stays the primary/default view for diabetic-type
              // users (this whole screen, and the bottom nav landing on
              // it) — this is just a way *in* to steps/sleep/heart-rate/
              // HRV, which used to be completely unreachable for this user
              // type (/activity forcibly redirected back here). Pushed,
              // not go()'d, so the back button returns here rather than
              // replacing this as the landing screen.
              _HealthActivityLink(onTap: () => context.push('/activity')),

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: _ActionBtn(
                      label: 'Log Reading',
                      color: AppTheme.brandPurpleDeep,
                      onPressed: () => _openManualEntry(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _ActionBtn(
                      label: 'Log Bolus',
                      color: AppTheme.brandGreen,
                      onPressed: () => context.push('/bolus/manual'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _ActionBtn(
                      label: 'Log Meal',
                      color: AppTheme.accentOrange,
                      onPressed: () => context.push('/meals'),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 80),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStripStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: AppTheme.labelSmall.copyWith(fontSize: 8, color: AppTheme.brandGreenDark.withValues(alpha: 0.6))),
        const SizedBox(height: 4),
        Text(value, style: AppTheme.titleLarge.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w900)),
      ],
    );
  }

  String _getStatusLabel(GlucoseStatus status) => switch (status) {
    GlucoseStatus.inRange => '● In Range',
    GlucoseStatus.high    => '● High',
    GlucoseStatus.veryHigh => '🚨 Very High',
    GlucoseStatus.low     => '⚠ Low',
  };

  Color _getStatusColor(GlucoseStatus status) => switch (status) {
    GlucoseStatus.inRange => AppTheme.brandGreen,
    GlucoseStatus.high    => AppTheme.glucoseHigh,
    GlucoseStatus.veryHigh => AppTheme.glucoseHyper,
    GlucoseStatus.low     => AppTheme.glucoseLow,
  };
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionBtn({required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTheme.labelLarge.copyWith(color: AppTheme.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Entry point into steps/sleep/heart-rate/HRV (ActivityScreen) for
/// diabetic-type users, who otherwise land on this glucose view by
/// default and have no bottom-nav tab of their own for it
/// (main_shell.dart shows exactly one of Glucose/Activity, chosen by user
/// type). Deliberately a modest link, not a big CTA — glucose stays
/// primary, this is "also reachable," not a second focal point.
class _HealthActivityLink extends StatelessWidget {
  final VoidCallback onTap;

  const _HealthActivityLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        child: Row(
          children: [
            const Icon(LucideIcons.watch, color: AppTheme.accentCyan),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Health & Activity', style: AppTheme.labelLarge),
                  Text(
                    'Steps, sleep, heart rate, and more',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
