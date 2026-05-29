import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../cgm/providers/cgm_connection_provider.dart';
import '../../../onboarding/onboarding_provider.dart';

// ── Placeholder data ─────────────────────────────────────────────────────────
// These will be replaced once the dashboard API endpoint is wired up.
// They are centralised here so it's obvious what still needs real data.
abstract class _DashboardPlaceholder {
  static const glucoseValue   = '118';
  static const glucoseUnit    = 'mg/dL';
  static const tirValue       = '74%';
  static const tirSubtitle    = 'Last 24 hrs';
  static const tddValue       = '22.4 u';
  static const tddSubtitle    = 'vs 24 avg';
  static const lastMeal       = 'Dinner';
  static const lastMealTime   = '8:30 PM Yesterday';
  static const lastBolus      = '4.2';
  static const bolusUnit      = 'units';
  static const adjustmentNote = '-16% lifestyle adjustment applied';
  static const modelConfidence = 'Low (62%)';
  static const sleepHrs       = '7.2 hrs';
  static const sleepProgress  = 0.8;
  static const activityLevel  = 'Light';
  static const activityProgress = 0.4;
  static const stressLevel    = 'Moderate';
  static const stressProgress = 0.6;
  static const calories       = '1,840';
  static const calorieProgress = 0.85;
  static const List<FlSpot> glucoseSparkline = [
    FlSpot(0, 100), FlSpot(1, 105), FlSpot(2, 110),
    FlSpot(3, 115), FlSpot(4, 118), FlSpot(5, 118),
  ];
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Simulate network fetch for 1.5 seconds to show shimmer
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _formattedNow {
    final now = DateTime.now();
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final day = weekdays[now.weekday - 1];
    final hour = now.hour > 12 ? now.hour - 12 : now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return '$day ${hour.toString()}:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Read first name from onboarding state (falls back to 'there' if not set)
    final firstName = ref.watch(
      onboardingProvider.select((s) {
        final full = s.personalInfo?.fullName ?? '';
        return full.isNotEmpty ? full.split(' ').first : 'there';
      }),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mytr.AI', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          )
        ],
      ),
      body: _isLoading
          ? _buildShimmerLoading(theme)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$_greeting, $firstName',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _formattedNow,
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  // Live Glucose Card
                  _buildLiveGlucoseCard(theme),
                  const SizedBox(height: 16),

                  // TIR & TDD Row
                  Row(
                    children: [
                      Expanded(child: _buildStatCard(theme, 'Time in Range', _DashboardPlaceholder.tirValue, _DashboardPlaceholder.tirSubtitle, Colors.green)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildStatCard(theme, "Today's TDD", _DashboardPlaceholder.tddValue, _DashboardPlaceholder.tddSubtitle, theme.colorScheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Next Action Card
                  _buildNextActionCard(theme),
                  const SizedBox(height: 16),

                  // Last Recommendation Card
                  _buildLastRecommendationCard(theme),
                  const SizedBox(height: 16),

                  // Lifestyle Score Card
                  _buildLifestyleScoreCard(theme),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildLiveGlucoseCard(ThemeData theme) {
    final cgmState = ref.watch(cgmConnectionProvider);
    final hasWarning = cgmState.connectedInfo?.isExpired == true || cgmState.connectedInfo?.noSensor == true;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: hasWarning ? Colors.amber.shade300 : Colors.grey.shade200),
      ),
      child: Column(
        children: [
          if (hasWarning)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Text(
                    cgmState.connectedInfo?.isExpired == true ? 'Sensor Expired' : 'No Active Sensor',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LIVE GLUCOSE', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      hasWarning ? '--' : _DashboardPlaceholder.glucoseValue, 
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.bold, 
                        color: hasWarning ? Colors.grey.shade400 : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_DashboardPlaceholder.glucoseUnit, style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey)),
                    const SizedBox(width: 12),
                    if (!hasWarning)
                      const Icon(Icons.arrow_forward, color: Colors.green, size: 28),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 60,
                  child: hasWarning 
                    ? Center(
                        child: Text(
                          'Start a new sensor session to see data',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      )
                    : LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: _DashboardPlaceholder.glucoseSparkline,
                              isCurved: true,
                              color: theme.colorScheme.primary,
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                              ),
                            ),
                          ],
                        ),
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      hasWarning ? Icons.error_outline : Icons.check_circle, 
                      color: hasWarning ? Colors.amber : Colors.green, 
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasWarning ? 'Action required' : 'In range', 
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      hasWarning ? 'Data unavailable' : 'Last updated 2m ago', 
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(ThemeData theme, String title, String value, String subtitle, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.labelMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildNextActionCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NEXT ACTION', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.restaurant, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Log breakfast to get your personalized bolus recommendation',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(minimumSize: const Size(120, 44)),
                child: const Text('Log Meal'),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildLastRecommendationCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            decoration: const BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: Colors.black87),
                SizedBox(width: 8),
                Text('Doctor review suggested', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LAST RECOMMENDATION', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_DashboardPlaceholder.lastMeal, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text(_DashboardPlaceholder.lastMealTime, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(_DashboardPlaceholder.lastBolus, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text(_DashboardPlaceholder.bolusUnit, style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_DashboardPlaceholder.adjustmentNote, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.green)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Model Confidence: ', style: theme.textTheme.bodySmall),
                    Text(_DashboardPlaceholder.modelConfidence, style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLifestyleScoreCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("TODAY'S LIFESTYLE", style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            _buildProgressRow(theme, 'Sleep',    _DashboardPlaceholder.sleepProgress,    _DashboardPlaceholder.sleepHrs,    theme.colorScheme.primary),
            const SizedBox(height: 12),
            _buildProgressRow(theme, 'Activity', _DashboardPlaceholder.activityProgress, _DashboardPlaceholder.activityLevel, Colors.orange),
            const SizedBox(height: 12),
            _buildProgressRow(theme, 'Stress',   _DashboardPlaceholder.stressProgress,   _DashboardPlaceholder.stressLevel,  Colors.amber),
            const SizedBox(height: 12),
            _buildProgressRow(theme, 'Calories', _DashboardPlaceholder.calorieProgress,  _DashboardPlaceholder.calories,    Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRow(ThemeData theme, String label, double progress, String value, Color color) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label, style: theme.textTheme.bodyMedium)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(width: 60, child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
      ],
    );
  }

  Widget _buildShimmerLoading(ThemeData theme) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 150, height: 24, color: Colors.white),
            const SizedBox(height: 8),
            Container(width: 100, height: 16, color: Colors.white),
            const SizedBox(height: 24),
            Container(width: double.infinity, height: 200, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Container(height: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)))),
                const SizedBox(width: 16),
                Expanded(child: Container(height: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)))),
              ],
            ),
            const SizedBox(height: 16),
            Container(width: double.infinity, height: 150, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
          ],
        ),
      ),
    );
  }
}
