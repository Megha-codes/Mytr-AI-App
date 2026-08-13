"""Groq chat completions with tool-calling (the analytics chatbot).
Mirrors gemini_service.py's shape: a small class wrapping one HTTP call,
api_key via constructor, a fresh httpx.AsyncClient per call, no
persistent connection to manage.

Design principle (explicit, non-negotiable — see services/chat/
conversation.py, which is what actually enforces it): this service only
ever returns what the model said — text, and/or which tool(s) it wants
called with what arguments. It never computes or fabricates a health
number itself; it has no access to any user data at all, only whatever
text is in the messages/tool results it's handed. Every number that ends
up in a reply to the user must come from a real tool result, not the
model's own "knowledge" of what a plausible glucose reading looks like.
This module is deliberately dumb — pure HTTP request/response shuttling,
same spirit as GeminiVisionService not doing any nutrition logic itself.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from typing import Any, Optional

import httpx

logger = logging.getLogger(__name__)

GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions"

# llama-3.3-70b-versatile: Groq's tool-calling-capable general model.
DEFAULT_MODEL = "llama-3.3-70b-versatile"


@dataclass
class ToolCall:
    id: str
    name: str
    arguments: dict[str, Any]


@dataclass
class GroqReply:
    content: Optional[str]
    tool_calls: list[ToolCall] = field(default_factory=list)

    @property
    def wants_tool_call(self) -> bool:
        return bool(self.tool_calls)


class GroqService:
    def __init__(self, api_key: str, model: str = DEFAULT_MODEL) -> None:
        self.api_key = api_key
        self.model = model

    async def chat(
        self,
        messages: list[dict[str, Any]],
        tools: Optional[list[dict[str, Any]]] = None,
        temperature: float = 0.2,
    ) -> GroqReply:
        """One turn of the OpenAI-compatible chat completions call Groq
        exposes. Returns either narration text, or one or more tool calls
        the caller is expected to actually execute and feed back in as a
        `role: "tool"` message on the next call — this method does not
        loop or execute anything itself.
        """
        if not self.api_key:
            raise RuntimeError("GROQ_API_KEY is not configured")

        payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "temperature": temperature,
        }
        if tools:
            payload["tools"] = tools
            payload["tool_choice"] = "auto"

        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                GROQ_API_URL,
                headers={"Authorization": f"Bearer {self.api_key}"},
                json=payload,
            )
            response.raise_for_status()

        data = response.json()
        try:
            message = data["choices"][0]["message"]
        except (KeyError, IndexError) as exc:
            logger.error("Unexpected Groq response structure: %s", data)
            raise ValueError("Groq returned an unexpected response") from exc

        tool_calls: list[ToolCall] = []
        for call in message.get("tool_calls") or []:
            fn = call.get("function", {})
            raw_arguments = fn.get("arguments") or "{}"
            try:
                arguments = json.loads(raw_arguments)
            except json.JSONDecodeError:
                logger.warning("Could not parse tool call arguments: %s", raw_arguments)
                arguments = {}
            tool_calls.append(ToolCall(
                id=call.get("id", ""),
                name=fn.get("name", ""),
                arguments=arguments,
            ))

        return GroqReply(content=message.get("content"), tool_calls=tool_calls)
