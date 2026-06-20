import 'package:flutter/material.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/app_colors.dart';

/// The 5-step prerequisite guide for LibreLinkUp.
class LibreSetupGuide extends StatelessWidget {
  const LibreSetupGuide({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StepRow(
          number: 1,
          title: 'Ensure sensor is active',
          detail: 'Make sure your Libre sensor is active and scanning in the FreeStyle LibreLink app.',
        ),
        _StepRow(
          number: 2,
          title: 'Open Connected Apps',
          detail: 'Open FreeStyle LibreLink and go to: Menu (☰) → Connected Apps → LibreLinkUp',
        ),
        _StepRow(
          number: 3,
          title: 'LibreLinkUp Account',
          detail: 'If you don\'t have a LibreLinkUp account, create one — it\'s free and separate from your main FreeStyle account.',
        ),
        _StepRow(
          number: 4,
          title: 'Enable Data Sharing',
          detail: 'Tap \'Enable\' on the Connections toggle. Your data will now be shareable.',
        ),
        _StepRow(
          number: 5,
          title: 'Return & Connect',
          detail: 'Return here and enter your LibreLinkUp email and password below.',
        ),
      ],
    );
  }
}

class _StepRow extends StatefulWidget {
  final int number;
  final String title;
  final String detail;

  const _StepRow({required this.number, required this.title, required this.detail});

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(color: AppColors.cyan, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        '${widget.number}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(color: AppColors.nearBlack, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Text(
                    widget.detail,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5, height: 1.4),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
