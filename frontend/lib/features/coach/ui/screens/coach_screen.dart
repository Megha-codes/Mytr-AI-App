import 'package:flutter/material.dart';

class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Coach', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Today'),
              Tab(text: 'Insights'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTodayTab(theme),
            _buildInsightsTab(theme),
            _buildHistoryTab(theme),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: TODAY
  // ==========================================
  Widget _buildTodayTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        Text('Your coach  •  Tuesday', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 24),
        
        // Morning Check-In Card
        _buildActionCard(
          theme: theme,
          title: 'MORNING CHECK-IN',
          icon: Icons.wb_sunny_outlined,
          color: Colors.orange,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You slept 7.2 hrs — good.', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 4),
              Text('Morning glucose is 118, slightly above your avg of 109.', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Dawn phenomenon window active\nBolus doses adjusted +10% until 9 AM',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Today's Focus Card
        _buildActionCard(
          theme: theme,
          title: "TODAY'S FOCUS",
          icon: Icons.track_changes,
          color: Colors.indigo,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your stress was high yesterday and glucose ran 18% above avg.', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text('Try a 10-min walk after lunch to offset this pattern.', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () {},
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Sensor Expiry Alert
        _buildActionCard(
          theme: theme,
          title: 'SENSOR EXPIRY',
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your Libre 3 sensor expires in 2 days.', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text('Order replacement'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({required ThemeData theme, required String title, required IconData icon, required Color color, required Widget content}) {
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
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ],
            ),
            const SizedBox(height: 16),
            content,
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: INSIGHTS
  // ==========================================
  Widget _buildInsightsTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        Text('Your insulin reduction pathway', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Based on your last 30 days:', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
        const SizedBox(height: 24),

        _buildPathwayCard(
          theme: theme,
          title: 'IF YOU IMPROVE SLEEP',
          icon: Icons.nights_stay,
          color: Colors.indigo,
          metrics: [
            'Current avg: 6.1 hrs',
            'Target: 7.5 hrs',
          ],
          impact: '-1.8 units/day reduction\nin average bolus dose',
        ),
        const SizedBox(height: 16),

        _buildPathwayCard(
          theme: theme,
          title: 'IF YOU ADD EVENING WALK',
          icon: Icons.directions_walk,
          color: Colors.teal,
          metrics: [
            '30 mins, 4x per week',
          ],
          impact: '-0.9 units/day reduction\nin post-dinner bolus',
        ),
        const SizedBox(height: 16),

        _buildPathwayCard(
          theme: theme,
          title: 'IF YOU REDUCE EVENING CARBS',
          icon: Icons.restaurant,
          color: Colors.orange,
          metrics: [
            'From avg 72g to 50g dinner',
          ],
          impact: '-1.1 units/day reduction',
        ),
        const SizedBox(height: 32),

        // Combined Potential Banner
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
            ]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Combined potential: -3.8 units/day', style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('That\'s -26% of your current TDD', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildPathwayCard({required ThemeData theme, required String title, required IconData icon, required Color color, required List<String> metrics, required String impact}) {
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
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ],
            ),
            const SizedBox(height: 16),
            ...metrics.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(m, style: theme.textTheme.bodyLarge),
            )),
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
            Text('Estimated impact:', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(impact, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.green)),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 3: HISTORY
  // ==========================================
  Widget _buildHistoryTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        Text('COACH LOG', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 16),
        
        _buildHistoryLog(theme, 'Walked 15 mins after lunch', 'Your 2hr post-meal spike was reduced by 32% compared to yesterday. Excellent job offsetting that high GL meal!', 'Yesterday'),
        const SizedBox(height: 12),
        
        _buildHistoryLog(theme, 'Low sleep detected', 'Sleep deficit drove insulin resistance up by ~12% today. Expect larger bolus recommendations until you catch up.', 'Monday'),
        const SizedBox(height: 12),
        
        _buildHistoryLog(theme, 'TIR Goal Met!', 'You hit 82% time in range this weekend. The combination of early dinners and increased steps is working.', 'Sunday'),
      ],
    );
  }

  Widget _buildHistoryLog(ThemeData theme, String title, String body, String time) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                Text(time, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Helpful?', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                const SizedBox(width: 12),
                InkWell(onTap: () {}, child: const Icon(Icons.thumb_up_outlined, size: 18, color: Colors.grey)),
                const SizedBox(width: 12),
                InkWell(onTap: () {}, child: const Icon(Icons.thumb_down_outlined, size: 18, color: Colors.grey)),
              ],
            )
          ],
        ),
      ),
    );
  }
}
