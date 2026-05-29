import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A debug utility to simulate WebSocket messages from the backend.
/// Useful for testing UI reactions without a live WebSocket server.
class WsDebugOverlay extends ConsumerWidget {
  const WsDebugOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.black87,
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'WS DEBUG CONSOLE',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _DebugBtn(
                  label: 'Simulate Glucose High',
                  onTap: () => _simulateGlucose(ref, 210, 'RISING_FAST', 'HIGH'),
                ),
                _DebugBtn(
                  label: 'Simulate Glucose Low',
                  onTap: () => _simulateGlucose(ref, 65, 'FALLING', 'LOW'),
                ),
                _DebugBtn(
                  label: 'Simulate Glucose Target',
                  onTap: () => _simulateGlucose(ref, 115, 'STABLE', 'TARGET'),
                ),
                _DebugBtn(
                  label: 'Unlock Achievement',
                  onTap: () => _simulateAchievement(ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _simulateGlucose(WidgetRef ref, int value, String trend, String status) {
    final payload = {
      'type': 'GLUCOSE_READING',
      'payload': {
        'current_glucose': value,
        'trend': trend,
        'status': status,
        'last_updated': 0,
        'tir_24h': 85.0,
        'avg_28d': 112.0,
        'tir_breakdown': {'below': 5.0, 'target': 85.0, 'above': 10.0},
        'history': [],
      }
    };
    
    // In a real app, we'd inject this into the stream. 
    // For debug, we can manually update the provider state if we want to bypass the real WS.
    // For now, this is a conceptual demo of how they can test.
    debugPrint('Simulating WS: ${jsonEncode(payload)}');
  }

  void _simulateAchievement(WidgetRef ref) {
    debugPrint('Simulating Achievement Unlock...');
  }
}

class _DebugBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DebugBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white10,
        foregroundColor: Colors.white,
      ),
      child: Text(label),
    );
  }
}
