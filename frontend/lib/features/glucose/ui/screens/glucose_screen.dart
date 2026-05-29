import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class GlucoseScreen extends StatefulWidget {
  const GlucoseScreen({super.key});

  @override
  State<GlucoseScreen> createState() => _GlucoseScreenState();
}

class _GlucoseScreenState extends State<GlucoseScreen> {
  int _timeWindowIndex = 0; // 0=3hr, 1=6hr, 2=12hr

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Glucose', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Live'),
              Tab(text: 'Trends'),
              Tab(text: 'Patterns'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildLiveTab(theme),
            _buildTrendsTab(theme),
            _buildPatternsTab(theme),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: LIVE
  // ==========================================
  Widget _buildLiveTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('118', style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                    const SizedBox(width: 8),
                    Text('mg/dL', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey)),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.arrow_forward, color: Colors.green),
                    const SizedBox(width: 8),
                    Text('In Range', style: theme.textTheme.titleMedium?.copyWith(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Chart
          SizedBox(
            height: 250,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: _buildLiveChart(theme),
            ),
          ),
          const SizedBox(height: 24),

          // Time Window Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('3hr')),
                ButtonSegment(value: 1, label: Text('6hr')),
                ButtonSegment(value: 2, label: Text('12hr')),
              ],
              selected: {_timeWindowIndex},
              onSelectionChanged: (Set<int> newSelection) {
                setState(() {
                  _timeWindowIndex = newSelection.first;
                });
              },
            ),
          ),
          const SizedBox(height: 32),

          // Recent Events
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RECENT EVENTS', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 16),
                _buildEventItem(theme, '08:15', Icons.medical_services_outlined, 'Bolus: 4.2 units recommended', isPrimary: true),
                _buildEventItem(theme, '08:12', Icons.restaurant_outlined, 'Breakfast logged (62g carbs)'),
                _buildEventItem(theme, '07:45', Icons.wb_sunny_outlined, 'Woke up — glucose: 112'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveChart(ThemeData theme) {
    return LineChart(
      LineChartData(
        minY: 40,
        maxY: 200,
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == 80 || value == 130) {
                  return Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 12));
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(y: 130, color: Colors.green.withValues(alpha: 0.2), strokeWidth: 1, dashArray: [5, 5]),
            HorizontalLine(y: 80, color: Colors.green.withValues(alpha: 0.2), strokeWidth: 1, dashArray: [5, 5]),
          ],
          verticalLines: [
            // Meal marker
            VerticalLine(x: 2.5, color: Colors.orange.withValues(alpha: 0.5), strokeWidth: 2, dashArray: [4, 4], label: VerticalLineLabel(show: true, labelResolver: (l) => '🍽', style: const TextStyle(fontSize: 16))),
            // Bolus marker
            VerticalLine(x: 3.5, color: theme.colorScheme.primary.withValues(alpha: 0.5), strokeWidth: 2, dashArray: [4, 4], label: VerticalLineLabel(show: true, labelResolver: (l) => '💧', style: const TextStyle(fontSize: 16))),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 105), FlSpot(1, 102), FlSpot(2, 98), 
              FlSpot(3, 115), FlSpot(4, 135), FlSpot(5, 125),
              FlSpot(6, 118)
            ],
            isCurved: true,
            color: theme.colorScheme.primary,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventItem(ThemeData theme, String time, IconData icon, String text, {bool isPrimary = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(time, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPrimary ? theme.colorScheme.primary.withValues(alpha: 0.1) : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: isPrimary ? theme.colorScheme.primary : Colors.grey.shade700),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(text, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: TRENDS
  // ==========================================
  Widget _buildTrendsTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('DAILY AVERAGES (14 DAYS)', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 24),
          
          // Bar Chart
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: 200,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(y: 130, color: Colors.green.withValues(alpha: 0.2), strokeWidth: 1),
                    HorizontalLine(y: 80, color: Colors.green.withValues(alpha: 0.2), strokeWidth: 1),
                  ],
                ),
                barGroups: [
                  _buildBar(0, 115, theme.colorScheme.primary),
                  _buildBar(1, 120, theme.colorScheme.primary),
                  _buildBar(2, 110, theme.colorScheme.primary),
                  _buildBar(3, 145, Colors.orange), // Above range average
                  _buildBar(4, 112, theme.colorScheme.primary),
                  _buildBar(5, 105, theme.colorScheme.primary),
                  _buildBar(6, 118, theme.colorScheme.primary),
                  _buildBar(7, 125, theme.colorScheme.primary),
                  _buildBar(8, 130, theme.colorScheme.primary),
                  _buildBar(9, 100, theme.colorScheme.primary),
                  _buildBar(10, 110, theme.colorScheme.primary),
                  _buildBar(11, 150, Colors.orange),
                  _buildBar(12, 115, theme.colorScheme.primary),
                  _buildBar(13, 108, theme.colorScheme.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Time in Range Breakdown
          Text('TIME IN RANGE BREAKDOWN', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  _buildTirRow(theme, 'In range (80–130)', '74%', Colors.green),
                  const SizedBox(height: 12),
                  _buildTirRow(theme, 'Above range', '18%', Colors.orange),
                  const SizedBox(height: 12),
                  _buildTirRow(theme, 'Below range', '8%', Colors.red),
                  const SizedBox(height: 20),
                  // Visual bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Expanded(flex: 8, child: Container(height: 12, color: Colors.red)),
                        Expanded(flex: 74, child: Container(height: 12, color: Colors.green)),
                        Expanded(flex: 18, child: Container(height: 12, color: Colors.orange)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Best Day Card
          Text('BEST DAY THIS WEEK', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Colors.green.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.green.withValues(alpha: 0.2))),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Sunday', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text('89% in range', style: theme.textTheme.titleMedium?.copyWith(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Slept 8.1 hrs, walked 42 mins', style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _buildBar(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ],
    );
  }

  Widget _buildTirRow(ThemeData theme, String label, String value, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Text(label, style: theme.textTheme.bodyMedium),
        const Spacer(),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ==========================================
  // TAB 3: PATTERNS
  // ==========================================
  Widget _buildPatternsTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PATTERNS DETECTED', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 24),
          
          _buildInsightCard(
            theme: theme,
            icon: Icons.nights_stay_outlined,
            title: 'Sleep → Glucose',
            description: 'On nights you slept < 6 hrs, your morning glucose averaged 142 mg/dL vs 108 on good sleep.',
            color: Colors.indigo,
          ),
          const SizedBox(height: 16),
          
          _buildInsightCard(
            theme: theme,
            icon: Icons.directions_walk,
            title: 'Post-walk glucose drop',
            description: 'Evening walks reduce your 2hr post-meal spike by ~28%.',
            color: Colors.teal,
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard({required ThemeData theme, required IconData icon, required String title, required String description, required Color color}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 16),
            Text(description, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {},
                child: const Text('See data'),
              ),
            )
          ],
        ),
      ),
    );
  }
}
