import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/dark_header.dart';
import '../../providers/chat_provider.dart';
import '../widgets/chat_widgets.dart';

/// The analytics chatbot (POST /chat) — always reached via push (see the
/// entry points on glucose_screen.dart / activity_screen.dart), so it
/// always has a real back target and never needs to be a bottom-nav tab.
/// Client-managed conversation: chatProvider holds the message list and
/// resends it as `history` with every new message, matching the
/// backend's stateless-per-request contract.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    // Runs after the frame that added the new bubble/typing-indicator
    // actually lays out, so maxScrollExtent reflects the new content.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    _scrollToBottom(); // for the user's own bubble, appended synchronously below
    await ref.read(chatProvider.notifier).sendMessage(text);
    _scrollToBottom(); // for the reply (or error banner) that just arrived
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: Column(
        children: [
          DarkHeader(
            eyebrow: 'ASSISTANT',
            eyebrowColor: AppTheme.brandGreen,
            title: 'Ask Mytr.AI',
            trailing: IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: AppTheme.textOnDark),
              onPressed: () => context.pop(),
            ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ChatErrorBanner(
                message: state.error!,
                onDismiss: () => ref.read(chatProvider.notifier).dismissError(),
              ),
            ),
          Expanded(
            child: state.messages.isEmpty && !state.isSending
                ? ChatEmptyState(onSuggestionTap: _send)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: state.messages.length + (state.isSending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.messages.length) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: TypingIndicator(),
                        );
                      }
                      return ChatBubble(message: state.messages[index]);
                    },
                  ),
          ),
          ChatInputBar(
            controller: _inputController,
            isSending: state.isSending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}
