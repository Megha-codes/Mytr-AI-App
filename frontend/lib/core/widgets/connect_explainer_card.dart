import 'package:flutter/material.dart';

class ConnectExplainerCard extends StatelessWidget {
  const ConnectExplainerCard({
    super.key,
    required this.icon,
    required this.title,
    required this.points,
  });

  final Widget icon;
  final String title;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            icon,
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ...points.map(
              (point) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 18, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(child: Text(point)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
