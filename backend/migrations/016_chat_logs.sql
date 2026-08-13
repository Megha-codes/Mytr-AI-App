-- 016_chat_logs.sql
-- Audit log for the analytics chatbot (Groq tool-calling). One row per
-- turn: a user message, an assistant reply, or a tool call/result. This
-- is write-only from the app's perspective — the client sends its own
-- conversation history each request (POST /chat's `history` field), so
-- nothing here is ever read back to reconstruct context. It exists
-- purely so every conversation is logged, per the explicit requirement
-- that this bot's real-data-only, no-medical-directives behavior be
-- auditable after the fact.

CREATE TABLE IF NOT EXISTS chat_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL,  -- groups every turn of one conversation
    role            TEXT NOT NULL,  -- 'user' | 'assistant' | 'tool'
    content         TEXT,           -- narration text; null for a pure tool-call turn
    tool_name       TEXT,           -- set only on tool-call/tool-result turns
    tool_arguments  JSONB,          -- what the model asked the tool to do
    tool_result     JSONB,          -- what the real backend function actually returned
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS chat_logs_user_conversation_idx
  ON chat_logs (user_id, conversation_id, created_at);
