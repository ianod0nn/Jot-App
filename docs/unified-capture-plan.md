# Plan: Unified AI Capture Call + Anthropic API Migration

**Status:** Proposed
**Date:** 2026-06-08
**Scope:** Replace the three competing categorization systems with a single structured AI call at capture time, and migrate the AI backend from OpenAI to Anthropic's API.

---

## Why

Three issues motivated this work:

1. **Not proactive** — the app never reminds you of anything. Tasks have no due date and there is no notification system. *(Out of scope here, but this plan lays the foundation — see "How this feeds the other features".)*
2. **Poor response formatting** — lists/dates render as raw text. *(Out of scope here; foundation only.)*
3. **Bad categorization** — the focus of this plan.

### Root cause of #3 (the smoking gun)

There are **three** categorization systems that don't agree:

- `DataManager.looksLikeTask()` — keyword list #1, sets `taskState` on capture ([DataManager.swift:123](../Jot/Services/DataManager.swift))
- `ChatView.classifyThought()` — keyword list #2, decides the "✓ Saved" acknowledgment ([ChatView.swift:194](../Jot/Views/ChatView.swift))
- `AIManager.categorizeThought()` — calls the LLM, returns `[TASK]/[IDEA]/[INFO]` ([AIManager.swift:26](../Jot/Services/AIManager.swift))

And the AI result is **thrown away** — [ChatView.swift:228-231](../Jot/Views/ChatView.swift):

```swift
Task {
    let categorizedText = await aiManager.categorizeThought(text)
    // Update the thought with category if needed   ← never implemented
}
```

So `CapturedThought.category` is **always `nil`**. The "smart" categorization has never actually run. The app has been operating entirely on brittle substring keyword matching.

---

## The core change

Replace all three systems with **one Anthropic call at capture time** that returns structured JSON. Persist it on the thought. Everything downstream (retention, task detection, query filtering, future reminders, future date cards) reads from it instead of re-guessing.

---

## Step 1 — Define the structured result

New file `Jot/Models/ThoughtAnalysis.swift`:

```swift
struct ThoughtAnalysis: Codable {
    enum Category: String, Codable { case task, idea, info }

    let category: Category
    let isTask: Bool
    let cleanedText: String      // lightly normalized version of the input
    let dueDate: Date?           // resolved absolute date if a time was mentioned
    let priority: Int?           // 1–3, optional
    let tags: [String]
}
```

---

## Step 2 — Migrate AIManager to the Anthropic API

Swift has no official Anthropic SDK, so we keep using `URLSession` with raw HTTP. Changes to [AIManager.swift](../Jot/Services/AIManager.swift):

### 2a. Endpoint, headers, auth

| | OpenAI (current) | Anthropic (new) |
|---|---|---|
| URL | `https://api.openai.com/v1/chat/completions` | `https://api.anthropic.com/v1/messages` |
| Auth header | `Authorization: Bearer <key>` | `x-api-key: <key>` |
| Extra header | — | `anthropic-version: 2023-06-01` |
| System prompt | a message with `role: "system"` | top-level `system` field |
| Response text | `choices[0].message.content` | first `text` block in `content[]` |

### 2b. Config key

`Config.plist`: rename `OpenAIAPIKey` → `AnthropicAPIKey`. Update `getAPIKey()` ([AIManager.swift:10](../Jot/Services/AIManager.swift)) and the dummy-key check ([AIManager.swift:267](../Jot/Services/AIManager.swift)). **The key still ships inside the app binary** — fine for a personal build; a proxy backend is the move if this is ever distributed.

### 2c. Model

Recommend **`claude-haiku-4-5`** for the per-capture call: it's the cheapest/fastest Claude model, supports structured outputs, and is the natural analog to the `gpt-4.1-nano` you were using. (Decision point — see "Open decisions" below. Higher quality: `claude-sonnet-4-6` or `claude-opus-4-8`.)

### 2d. Structured output (replaces "ask for JSON in the prompt")

Anthropic constrains output to a schema via `output_config.format`. New request body:

```json
{
  "model": "claude-haiku-4-5",
  "max_tokens": 400,
  "system": "<analysis instructions + today's date/time + timezone + few-shot examples>",
  "messages": [{ "role": "user", "content": "<the captured thought>" }],
  "output_config": {
    "format": {
      "type": "json_schema",
      "schema": {
        "type": "object",
        "properties": {
          "category":    { "type": "string", "enum": ["task", "idea", "info"] },
          "isTask":      { "type": "boolean" },
          "cleanedText": { "type": "string" },
          "dueDate":     { "type": "string", "format": "date-time" },
          "priority":    { "type": "integer", "enum": [1, 2, 3] },
          "tags":        { "type": "array", "items": { "type": "string" } }
        },
        "required": ["category", "isTask", "cleanedText", "tags"],
        "additionalProperties": false
      }
    }
  }
}
```

Notes:
- `dueDate` is **optional** (omit from `required`) — only present when the thought mentions a time. Decode with an ISO-8601 strategy.
- Put **today's date/time and the user's timezone in the `system` prompt** so "tomorrow at 3" resolves to a real `dueDate`. `Date()` and `TimeZone.current` are available in-app.
- JSON-schema limits to respect: no `minLength`/`maximum`/etc. constraints, no recursion, and `additionalProperties: false` is required. Our schema is within these.
- Decode the first `text` block of `content[]` into `ThoughtAnalysis` with `JSONDecoder`.

### 2e. New method

Replace `categorizeThought` with:

```swift
func analyzeThought(_ text: String) async -> ThoughtAnalysis?
```

If the call fails or JSON is malformed, return `nil` and **fall back** to the existing `looksLikeTask` keyword check so capture never blocks on the network.

---

## Step 3 — Persist it (fix the discarded-result bug)

Two additive, **optional** model fields (so existing UserDefaults data still decodes — missing keys → `nil`):

- `ChatMessage`: add `var category: String?` and `var dueDate: Date?`
- `CapturedThought`: add `var messageId: UUID?` (links back to its chat bubble) and `var dueDate: Date?`

Then fix [ChatView.swift:228-231](../Jot/Views/ChatView.swift):

```swift
Task {
    guard let analysis = await aiManager.analyzeThought(text) else { return }
    await MainActor.run {
        dataManager.applyAnalysis(analysis, toMessageId: messageId, thoughtId: thoughtId)
    }
}
```

`addUserMessage` returns the two ids; a new `DataManager.applyAnalysis(...)` updates `taskState`, `category`, and `dueDate` in place and re-saves. Capture stays instant (optimistic); analysis fills in a moment later.

---

## Step 4 — Delete the duplicate heuristics

- `ChatView.classifyThought()` → **delete**; drive the "✓ Saved" decision off `analysis.category`.
- `DataManager.looksLikeTask()` → **demote** to fallback-only (used when the AI call fails).
- Query filtering ([AIManager.filterThoughtsForQuery](../Jot/Services/AIManager.swift:63)) and retention ([shouldKeepForever](../Jot/Services/DataManager.swift:148)) now read the now-populated `thought.category` instead of substring matching.

Also migrate the **query** path (`queryThoughts`) to the same Anthropic request/response shape as Step 2.

---

## How this feeds the other two features

- **Reminders (#1):** `analysis.dueDate` is the missing piece. When non-nil, schedule a `UNUserNotificationCenter` notification. No extra parsing later.
- **Date cards (#2):** when `dueDate != nil`, the bubble can render a date/calendar card + "Add to Calendar" (EventKit) instead of plain text. (Separately, render AI responses as `AttributedString(markdown:)` so lists show as bullets — a one-line fix in [ChatBubbleView.swift:62](../Jot/Views/ChatBubbleView.swift).)

---

## Open decisions

- **Model for the per-capture call** — `claude-haiku-4-5` (recommended, cheap/fast) vs `claude-sonnet-4-6` / `claude-opus-4-8` (higher quality, more cost). Every captured thought triggers one call.
- **One call vs two** — fold categorization + task-detection + date-extraction into the single `analyzeThought` call (recommended), eliminating the duplicate heuristics entirely.

---

## Risks

| Item | Note |
|---|---|
| Latency | One call at capture (~1s on Haiku). Optimistic UI hides it. |
| Cost | Now categorizing *every* thought (the call was wasted before anyway). Haiku is cheap. |
| JSON reliability | `output_config.format` guarantees schema-valid output; `nil` fallback covers transport errors. |
| Two-store split | `messages` and `thoughts` are duplicated today. This plan *links* them via `messageId` rather than merging — a larger refactor kept out of scope. |
| API key in binary | Unchanged from today; acceptable for personal use, revisit if distributed. |

## Scope of edits

1 new file (`ThoughtAnalysis.swift`), edits to `AIManager`, `DataManager`, `ChatView`, the two model structs, and `Config.plist`. No new dependencies. ~half a day.
