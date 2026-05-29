import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';

/// Animated prerequisite checklist shown before the Dexcom OAuth button.
/// Teaches the user what they need before connecting.
class DexcomPrereqChecklist extends StatefulWidget {
  const DexcomPrereqChecklist({super.key});

  @override
  State<DexcomPrereqChecklist> createState() => _DexcomPrereqChecklistState();
}

class _DexcomPrereqChecklistState extends State<DexcomPrereqChecklist> {
  final List<_Prereq> _prereqs = [
    _Prereq(
      label: 'A Dexcom account',
      detail: 'Created when you set up your Dexcom receiver or mobile app.',
    ),
    _Prereq(
      label: 'Dexcom Share enabled',
      detail: 'Dexcom app → Menu → Settings → Share → Enable Sharing.',
      hasHowTo: true,
    ),
    _Prereq(
      label: 'An active sensor session',
      detail: 'Your sensor must be inserted and past its warm-up period.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F8FF),
        border: Border.all(color: const Color(0xFF9DDBF0), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.clipboardCheck, 
                  color: AppColors.cyan, size: 14),
              SizedBox(width: 8),
              Text(
                'Before you connect',
                style: TextStyle(
                  color: Color(0xFF006A8A),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._prereqs.map((p) => _PrereqRow(prereq: p)),
        ],
      ),
    );
  }
}

class _Prereq {
  final String label;
  final String detail;
  final bool hasHowTo;
  bool checked = false; // mutated directly, never passed via constructor

  _Prereq({
    required this.label,
    required this.detail,
    this.hasHowTo = false,
  });
}

class _PrereqRow extends StatefulWidget {
  final _Prereq prereq;
  const _PrereqRow({required this.prereq});

  @override
  State<_PrereqRow> createState() => _PrereqRowState();
}

class _PrereqRowState extends State<_PrereqRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => 
                    widget.prereq.checked = !widget.prereq.checked),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: widget.prereq.checked
                        ? AppColors.cyan
                        : Colors.transparent,
                    border: Border.all(
                      color: widget.prereq.checked
                          ? AppColors.cyan
                          : const Color(0xFF9DDBF0),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: widget.prereq.checked
                      ? const Icon(LucideIcons.check,
                          color: Colors.white, size: 12)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.prereq.label,
                  style: TextStyle(
                    color: widget.prereq.checked
                        ? const Color(0xFF006A8A)
                        : const Color(0xFF007AA0),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    decoration: widget.prereq.checked
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              if (widget.prereq.hasHowTo)
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: const Text(
                    'How?',
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.cyan,
                    ),
                  ),
                ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                widget.prereq.detail,
                style: const TextStyle(
                  color: Color(0xFF007AA0),
                  fontSize: 8,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
