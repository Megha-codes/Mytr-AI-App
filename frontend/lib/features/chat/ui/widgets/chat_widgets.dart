import 'package:flutter/material.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../providers/chat_provider.dart';

// ── Message bubble ──────────────────────────────────────────────────────

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.brandGreen : AppTheme.backgroundWhite,
          border: isUser ? null : Border.all(color: AppTheme.borderLight),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: Text(
          message.content,
          style: AppTheme.bodyMedium.copyWith(
            color: isUser ? Colors.white : AppTheme.textPrimary,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

// ── Typing indicator ─────────────────────────────────────────────────────

/// Shown while waiting on the backend — a real reply can take a few
/// seconds (Groq itself, plus a real tool call against the database in
/// between), so this is a genuine "still working" signal, not a flash.
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundWhite,
          border: Border.all(color: AppTheme.borderLight),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brandGreen),
            ),
            const SizedBox(width: 10),
            Text('Thinking…', style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────

class ChatErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const ChatErrorBanner({super.key, required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.glucoseHyper.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glucoseHyper.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertCircle, size: 16, color: AppTheme.glucoseHyper),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: AppTheme.bodySmall.copyWith(color: AppTheme.textPrimary)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(LucideIcons.x, size: 16, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────

const List<String> _suggestedPrompts = [
  'How was my glucose this week?',
  'I ate 2 rotis',
  'Log a glass of water',
];

class ChatEmptyState extends StatelessWidget {
  final ValueChanged<String> onSuggestionTap;

  const ChatEmptyState({super.key, required this.onSuggestionTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.sparkles, size: 32, color: AppTheme.brandGreen),
            const SizedBox(height: 16),
            Text(
              'Ask about your data, or log something',
              textAlign: TextAlign.center,
              style: AppTheme.titleMedium.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'I only ever report your real logged data — for insulin doses or '
              'medication changes, always check with your doctor.',
              textAlign: TextAlign.center,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _suggestedPrompts
                  .map((prompt) => _SuggestionChip(text: prompt, onTap: () => onSuggestionTap(prompt)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _SuggestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.brandGreenLight,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(text, style: AppTheme.labelLarge.copyWith(color: AppTheme.brandGreenDark, fontSize: 12)),
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final ValueChanged<String> onSend;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  void _submit() {
    final text = controller.text;
    if (text.trim().isEmpty || isSending) return;
    onSend(text);
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppTheme.backgroundWhite,
          border: Border(top: BorderSide(color: AppTheme.borderLight)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  enabled: !isSending,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Ask or log something…',
                    hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textHint),
                    filled: true,
                    fillColor: AppTheme.backgroundSurface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(enabled: !isSending, onTap: _submit),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _SendButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled ? AppTheme.brandGreen : AppTheme.borderLight,
          shape: BoxShape.circle,
        ),
        child: Icon(
          LucideIcons.arrowUp,
          color: enabled ? Colors.white : AppTheme.textHint,
          size: 20,
        ),
      ),
    );
  }
}
