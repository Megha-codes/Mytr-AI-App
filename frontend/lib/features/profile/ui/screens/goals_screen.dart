import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../providers/goals_provider.dart';

/// Opens the interactive goal-setting sheet as a modal bottom sheet.
Future<void> showGoalSettingSheet(BuildContext context, WidgetRef ref) {
  final goals = ref.read(goalsProvider).valueOrNull ?? const Goals();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.backgroundCream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _GoalEditor(initial: goals, asSheet: true),
  );
}

/// Full-screen variant used by the /profile/goals route.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalsProvider);
    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      appBar: AppBar(
        title: const Text('Your Goals'),
        backgroundColor: AppTheme.backgroundCream,
        elevation: 0,
      ),
      body: goalsAsync.when(
        data: (goals) => SingleChildScrollView(
          child: _GoalEditor(initial: goals, asSheet: false),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _GoalEditor(initial: const Goals(), asSheet: false),
      ),
    );
  }
}

class _GoalEditor extends ConsumerStatefulWidget {
  final Goals initial;
  final bool asSheet;
  const _GoalEditor({required this.initial, required this.asSheet});

  @override
  ConsumerState<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<_GoalEditor> {
  late final TextEditingController _weightCtrl;
  late int _stepGoal;
  late int _calorieGoal;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController(
      text: widget.initial.weightGoalKg != null
          ? widget.initial.weightGoalKg!.toStringAsFixed(0)
          : '',
    );
    _stepGoal = widget.initial.dailyStepGoal;
    _calorieGoal = widget.initial.dailyCalorieGoal;
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final weight = double.tryParse(_weightCtrl.text.trim());
    final goals = Goals(
      weightGoalKg: weight,
      dailyStepGoal: _stepGoal,
      dailyCalorieGoal: _calorieGoal,
    );
    await ref.read(goalsProvider.notifier).save(goals);
    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.asSheet) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goals saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        widget.asSheet ? 20 : 8,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.asSheet) ...[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Set your goals', style: AppTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Personalise your targets. You can change these anytime.',
              style: AppTheme.bodySmall,
            ),
            const SizedBox(height: 24),
          ],

          // ── Weight goal ──────────────────────────────────────────────────
          _label('🎯  Target weight'),
          const SizedBox(height: 8),
          TextField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'e.g. 70',
              suffixText: 'kg',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.borderLight),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Daily steps ──────────────────────────────────────────────────
          _label('👟  Daily step goal'),
          _valueRow('$_stepGoal steps'),
          Slider(
            value: _stepGoal.toDouble(),
            min: 2000,
            max: 20000,
            divisions: 36,
            activeColor: AppTheme.brandGreen,
            label: '$_stepGoal',
            onChanged: (v) => setState(() => _stepGoal = (v / 500).round() * 500),
          ),
          const SizedBox(height: 16),

          // ── Daily calories ───────────────────────────────────────────────
          _label('🔥  Daily calorie target'),
          _valueRow('$_calorieGoal kcal'),
          Slider(
            value: _calorieGoal.toDouble(),
            min: 1200,
            max: 4000,
            divisions: 28,
            activeColor: AppTheme.accentOrange,
            label: '$_calorieGoal',
            onChanged: (v) => setState(() => _calorieGoal = (v / 100).round() * 100),
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Save goals',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) =>
      Text(text, style: AppTheme.labelLarge.copyWith(fontSize: 13));

  Widget _valueRow(String value) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const Icon(LucideIcons.target, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(value, style: AppTheme.bodyMedium),
          ],
        ),
      );
}
