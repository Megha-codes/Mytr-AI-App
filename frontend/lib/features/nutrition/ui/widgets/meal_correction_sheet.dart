import 'package:flutter/material.dart';

class MealCorrectionSheet extends StatefulWidget {
  final String mealLogId;
  final List<dynamic> currentItems;

  const MealCorrectionSheet({super.key, required this.mealLogId, required this.currentItems});

  @override
  State<MealCorrectionSheet> createState() => _MealCorrectionSheetState();
}

class _MealCorrectionSheetState extends State<MealCorrectionSheet> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    String initialText = widget.currentItems.map((e) => e['name']).join(', ');
    _controller = TextEditingController(text: initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // In a real app, this sends the corrected text back to /api/v1/nutrition/correct
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Correct Meal Items', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),
          const Text('What did you actually eat?'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. Masala Dosa, Idli',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Update & Recalculate'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
