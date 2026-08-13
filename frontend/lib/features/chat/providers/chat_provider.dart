import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';

/// Mirrors backend POST /chat (the analytics chatbot): the model handles
/// conversation only, every real number in a reply comes from a tool call
/// against real backend data — this provider's job is just shuttling
/// messages back and forth and holding the client-side conversation state
/// the backend expects each request to carry (it has no server-side
/// session; `history` is replayed every call).
class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class ChatState {
  final List<ChatMessage> messages;
  final bool isSending;
  final String? error;
  final String? conversationId;

  const ChatState({
    this.messages = const [],
    this.isSending = false,
    this.error,
    this.conversationId,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isSending,
    String? error,
    bool clearError = false,
    String? conversationId,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
      conversationId: conversationId ?? this.conversationId,
    );
  }
}

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    // history = everything before this new message, matching the
    // backend's contract (ChatRequest.message is the new turn,
    // ChatRequest.history is prior turns) — captured before appending the
    // user's message to local state below.
    final history = state.messages;
    final userMessage = ChatMessage(role: 'user', content: trimmed);
    state = state.copyWith(
      messages: [...history, userMessage],
      isSending: true,
      clearError: true,
    );

    try {
      final response = await ref.read(apiClientProvider).post(
        '/chat',
        data: {
          'message': trimmed,
          'history': history.map((m) => m.toJson()).toList(),
          if (state.conversationId != null) 'conversation_id': state.conversationId,
        },
        // Groq + a tool-call round trip can take longer than this app's
        // default 15s receive timeout (a real "how was my glucose this
        // week" call measured ~3-12s end to end, and a slower multi-tool
        // turn could run longer) — widened just for this call rather than
        // the whole ApiClient, which would mask a genuinely-hung request
        // on every other endpoint for 45s instead of 15.
        options: Options(receiveTimeout: const Duration(seconds: 45)),
      );
      final data = response.data as Map<String, dynamic>;
      final reply = data['reply'] as String? ?? '';
      final conversationId = data['conversation_id'] as String?;

      state = state.copyWith(
        messages: [...state.messages, ChatMessage(role: 'assistant', content: reply)],
        isSending: false,
        conversationId: conversationId,
      );
    } catch (e) {
      // The user's message stays visible (it really was sent) — only the
      // reply failed to come back. Retrying re-sends the same message as
      // a new turn, which is simpler and safer than trying to resume a
      // half-finished tool-call loop from the client side.
      state = state.copyWith(isSending: false, error: _friendlyError(e));
    }
  }

  void dismissError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
          return "Can't reach the server — check your connection and try again.";
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return 'That took too long to answer — please try again.';
        default:
          break;
      }
      final status = error.response?.statusCode;
      if (status == 429) {
        return "I'm getting a lot of requests right now — please wait a moment and try again.";
      }
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
    }
    return 'Something went wrong — please try again.';
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
