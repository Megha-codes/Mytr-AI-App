import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'meal_correction_sheet.dart';

// Dummy class to match structure
class MealRecognitionResult {
  final String mealLogId;
  final List<dynamic> foodItems;
  final Map<String, dynamic> totals;
  final Map<String, dynamic>? recommendation;
  final double recognitionConfidence;
  final bool requiresConfirmation;
  final String? confirmationMessage;

  MealRecognitionResult({
    required this.mealLogId,
    required this.foodItems,
    required this.totals,
    this.recommendation,
    required this.recognitionConfidence,
    required this.requiresConfirmation,
    this.confirmationMessage,
  });
}

class MealRecognitionCard extends ConsumerWidget {
  final MealRecognitionResult result;

  const MealRecognitionCard({super.key, required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        
        // Low Confidence Banner
        if (result.requiresConfirmation)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    result.confirmationMessage ?? 'Please verify these items.',
                    style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

        // Food identification card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        result.foodItems.map((f) => f['name']).join(", "),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Confidence indicator
                    ConfidencePill(confidence: result.recognitionConfidence),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildMacroStat(context, 'Carbs', '${result.totals['carbs_g']}g')),
                    Expanded(child: _buildMacroStat(context, 'GL', '${result.totals['glycaemic_load']}')),
                    Expanded(child: _buildMacroStat(context, 'Calories', '${result.totals['calories']}')),
                    Expanded(child: _buildMacroStat(context, 'Protein', '${result.totals['protein_g']}g')),
                  ],
                ),
                const SizedBox(height: 12),
                // "Not right?" correction button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _showCorrectionSheet(context, ref),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text("Not right?"),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Bolus recommendation card (Disabled if low confidence)
        if (!result.requiresConfirmation && result.recommendation != null)
          _buildBolusCard(context)
        else
          Opacity(
            opacity: 0.5,
            child: _buildBolusCard(context, disabled: true),
          )
      ],
    );
  }

  Widget _buildMacroStat(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildBolusCard(BuildContext context, {bool disabled = false}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: disabled ? Colors.grey.shade100 : theme.colorScheme.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: disabled ? Colors.grey.shade300 : theme.colorScheme.primary.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('BOLUS RECOMMENDATION', style: theme.textTheme.labelSmall?.copyWith(color: disabled ? Colors.grey : theme.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                Icon(Icons.psychology, color: disabled ? Colors.grey : Colors.indigo, size: 20),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(disabled ? '--' : '${result.recommendation?['recommended_bolus'] ?? 3.8}', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: disabled ? Colors.grey : theme.colorScheme.primary)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text('units', style: theme.textTheme.titleMedium?.copyWith(color: disabled ? Colors.grey : theme.colorScheme.primary)),
                ),
              ],
            ),
            if (!disabled) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: Text('-24% lifestyle adjustment', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 24),
              Text('Why?', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildDriverItem(theme, Icons.check_circle, Colors.green, 'Walk 40 mins ago improved sensitivity'),
              const SizedBox(height: 8),
              _buildDriverItem(theme, Icons.check_circle, Colors.green, 'Glucose stable in range'),
              const SizedBox(height: 8),
              _buildDriverItem(theme, Icons.warning_amber_rounded, Colors.orange, 'Moderate GL meal may spike later'),
              const Padding(padding: EdgeInsets.symmetric(vertical: 16.0), child: Divider()),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Model Confidence:', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700)),
                  Row(
                    children: [
                      Text('High  ', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.green)),
                      const Text('●●●●○', style: TextStyle(color: Colors.green, fontSize: 10, letterSpacing: 2)),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(side: BorderSide(color: theme.colorScheme.primary), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Ask doctor'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Confirm'),
                    ),
                  ),
                ],
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildDriverItem(ThemeData theme, IconData icon, Color color, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }

  void _showCorrectionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MealCorrectionSheet(
        mealLogId: result.mealLogId,
        currentItems: result.foodItems,
      ),
    );
  }
}

class ConfidencePill extends StatelessWidget {
  final double confidence;   // 0.0 – 1.0

  const ConfidencePill({super.key, required this.confidence});

  @override
  Widget build(BuildContext context) {
    final label = confidence >= 0.8 ? "High confidence"
        : confidence >= 0.6 ? "Moderate confidence"
        : "Low confidence — verify";

    final color = confidence >= 0.8 ? Colors.green
        : confidence >= 0.6 ? Colors.orange
        : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}
