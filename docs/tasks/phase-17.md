# Phase 17 — Multi-provider (Ollama / LM Studio / OpenAI / Anthropic / Gemini)

## Phase

Phase 17 of the production master plan. Makes the `Agent` dropdown
actually multi-provider. Five providers via a unified `LLMClient`
protocol. Each provider's API is implemented as a separate concrete
client. Streaming is preserved across all providers.

## References

- `docs/MASTER_SPEC.md` §12 (LLM Integration)
- `docs/MASTER_SPEC.md` §15 (Persistence) — per-provider Keychain
- `docs/MASTER_SPEC.md` Appendix B / C

## Focus

Extract the LLM API surface (chat streaming + model listing) into a
protocol. Add four new providers alongside the existing Ollama. The
`AgentProvider` enum's Picker in Settings now does real work — choosing
a provider changes the endpoint default, the Keychain account for the
API token, and the API call path. Existing single-Ollama users
experience zero behavior change unless they switch the provider.

Files to add:
- `Sources/TunaPop/LLMClient.swift` — protocol + shared types
- `Sources/TunaPop/LLMClientFactory.swift` — provider → client
- `Sources/TunaPop/OpenAIClient.swift` — OpenAI + LM Studio (compat)
- `Sources/TunaPop/AnthropicClient.swift`
- `Sources/TunaPop/GeminiClient.swift`

Files to modify:
- `Sources/TunaPop/AgentProvider.swift` — add four cases + defaults
- `Sources/TunaPop/OllamaClient.swift` — adopt `LLMClient` protocol;
  rename internal `OllamaStreamEvent` → `LLMStreamEvent`,
  `OllamaChatResult` → `LLMChatResult` (move types into LLMClient.swift)
- `Sources/TunaPop/AppSettings.swift` — provider-aware endpoint /
  Keychain account
- `Sources/TunaPop/SettingsView.swift` — Provider Picker drives the
  endpoint/model/token rows
- `Sources/TunaPop/PopupController.swift` — use `LLMClientFactory`

Files NOT to modify:
- everything else.

## Constraints

- macOS 14+, Swift 5.9+. No new third-party deps.
- `@MainActor` everywhere AppKit/SwiftUI mutates. Client types are
  value-type `struct`s (`Sendable`) and may be created on any actor;
  consumption happens on `@MainActor` (existing PopupController flow).
- `swift build` MUST succeed with zero new warnings.
- Backward compat: existing single-endpoint / single-token / single-
  model users keep working. The migration on first launch after this
  PR maps current `endpoint`, `model`, and Keychain token into the
  `ollama` slots.
- Streaming MUST work for ALL four new providers. Each parses its
  provider's specific streaming format.
- `URLError(.cancelled)` and `CancellationError` MUST be silent
  (existing rule).
- API tokens for the four new providers MUST be persisted in
  Keychain (per-provider account). For `ollama` keep current
  account name `"ollama"`.
- Logger usage: per-call logging at `.info`/`.error` for network
  failures. NEVER log tokens, full URLs with query, or user
  content. `.debug` for diagnostic only.

---

## Required types

### `LLMClient.swift` (new)

```swift
import Foundation

enum LLMStreamEvent: Sendable {
    case chunk(String)
    case done(LLMChatResult)
}

struct LLMChatResult: Equatable, Sendable {
    let content: String
    let model: String
    let promptTokens: Int
    let completionTokens: Int
}

enum LLMClientError: LocalizedError, Sendable {
    case invalidEndpoint
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Invalid endpoint."
        case .requestFailed(let m): return m
        }
    }
}

protocol LLMClient: Sendable {
    var provider: AgentProvider { get }

    func listModels() async throws -> [String]

    func chatStream(
        model: String,
        prompt: String,
        payload: SelectionPayload,
        includeSelectionContext: Bool,
        systemPrompt: String?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>
}
```

The existing `OllamaStreamEvent` and `OllamaChatResult` are REMOVED
from `OllamaClient.swift` and the public API surface migrates to
`LLMStreamEvent` / `LLMChatResult`. `OllamaError` stays for now to
satisfy any internal references; new code throws `LLMClientError`.

`PopupController.handleAction` switches the `for try await event in
stream { switch event { case .chunk(...): / case .done(...): ... }}`
loop to reference `LLMStreamEvent`. The metadata extraction now reads
`result.promptTokens + result.completionTokens`.

### `AgentProvider.swift` change

```swift
enum AgentProvider: String, CaseIterable, Codable, Identifiable {
    case ollama
    case lmStudio
    case openai
    case anthropic
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama:    return "Ollama"
        case .lmStudio:  return "LM Studio"
        case .openai:    return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini:    return "Gemini"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .ollama:    return "http://localhost:11434"
        case .lmStudio:  return "http://localhost:1234"
        case .openai:    return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini:    return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var keychainAccount: String { rawValue }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama, .lmStudio: return false
        case .openai, .anthropic, .gemini: return true
        }
    }
}
```

### `AppSettings.swift` change — per-provider endpoint + tokens

Replace the single `endpoint` / `apiToken` model with per-provider
storage. Keep the existing single `endpoint` / `apiToken` published
properties as a **derived view** of the active provider's slot so
existing SettingsView bindings keep working with minimal churn.

```swift
@Published var endpoints: [AgentProvider: String] {
    didSet { persistEndpoints() }
}

var endpoint: String {
    get { endpoints[agentProvider] ?? agentProvider.defaultEndpoint }
    set {
        endpoints[agentProvider] = newValue
    }
}

@Published var apiTokenForActiveProvider: String {
    didSet {
        try? KeychainHelper.set(apiTokenForActiveProvider, forAccount: agentProvider.keychainAccount)
    }
}

// Replace the old `apiToken` property's accessors with this binding.
var apiToken: String {
    get { apiTokenForActiveProvider }
    set { apiTokenForActiveProvider = newValue }
}
```

In `init()`:

1. Load `endpoints` map from UserDefaults under key `endpointsPerProvider`
   (JSON `[String: String]`). If absent, seed from defaults + migration.
2. Migration: if legacy single `endpoint` key exists in UserDefaults,
   copy it into `endpoints[.ollama]` and remove the legacy key. Same
   for the legacy single `apiToken` → Keychain account `ollama`.
3. Load `apiTokenForActiveProvider` from
   `KeychainHelper.get(forAccount: agentProvider.keychainAccount) ?? ""`
   AFTER `agentProvider` has been loaded.

`agentProvider`'s `didSet` MUST refresh `apiTokenForActiveProvider`
from Keychain so the SettingsView SecureField shows the right
token when the user switches provider:

```swift
@Published var agentProvider: AgentProvider {
    didSet {
        UserDefaults.standard.set(agentProvider.rawValue, forKey: Self.agentProviderKey)
        apiTokenForActiveProvider = KeychainHelper.get(forAccount: agentProvider.keychainAccount) ?? ""
    }
}
```

`endpoints[agentProvider]` getter/setter pattern keeps the existing
`$settings.endpoint` SwiftUI bindings working — SwiftUI re-reads when
`agentProvider` or `endpoints` `@Published` change.

### `LLMClientFactory.swift` (new)

```swift
import Foundation

@MainActor
enum LLMClientFactory {
    static func make(for settings: AppSettings) -> LLMClient {
        let endpoint = settings.endpoint
        let token = settings.apiToken
        switch settings.agentProvider {
        case .ollama:
            return OllamaClient(endpoint: endpoint, token: token)
        case .lmStudio:
            return OpenAIClient(
                provider: .lmStudio,
                endpoint: endpoint,
                token: token
            )
        case .openai:
            return OpenAIClient(
                provider: .openai,
                endpoint: endpoint,
                token: token
            )
        case .anthropic:
            return AnthropicClient(endpoint: endpoint, token: token)
        case .gemini:
            return GeminiClient(endpoint: endpoint, token: token)
        }
    }
}
```

### `OllamaClient.swift` change

Adopt the protocol:

```swift
struct OllamaClient: LLMClient {
    var provider: AgentProvider { .ollama }
    var endpoint: String
    var token: String

    // listModels(): /api/tags (existing, return [String])
    // chatStream(): /api/chat stream:true (existing, but yields LLMStreamEvent)
}
```

Rename the existing `OllamaStreamEvent` → use `LLMStreamEvent`.
Rename the existing `OllamaChatResult` → use `LLMChatResult` (fields
renamed: `evalCount` → `completionTokens`, `promptEvalCount` →
`promptTokens`).

The non-streaming `chat(...)` method MAY remain as an internal helper
or be removed — caller (`PopupController`) only uses streaming now.
Removing it shrinks the surface; keep if test paths depend on it.

### `OpenAIClient.swift` (new) — OpenAI + LM Studio

LM Studio implements the OpenAI Chat Completions API verbatim. One
client serves both.

```swift
struct OpenAIClient: LLMClient {
    var provider: AgentProvider
    var endpoint: String
    var token: String

    func listModels() async throws -> [String] {
        // GET /models
        // Response: { "data": [{ "id": "gpt-4o-mini", ... }, ...] }
    }

    func chatStream(...) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        // POST /chat/completions stream:true
        // Body: { "model":"...", "messages":[{"role":"system","content":"..."}, {"role":"user","content":"..."}], "stream":true, "stream_options":{"include_usage":true} }
        // Headers: Authorization: Bearer <token>
        // Response: text/event-stream
        //   data: {"id":"...", "choices":[{"delta":{"content":"hello"}}]}\n\n
        //   data: {"id":"...", "choices":[{"delta":{},"finish_reason":"stop"}], "usage":{"prompt_tokens":..., "completion_tokens":...}}\n\n
        //   data: [DONE]\n\n
    }
}
```

Streaming parser:
- Use `URLSession.bytes(for:)` `.lines`.
- For each line: strip prefix `"data: "`. If body is `"[DONE]"`,
  emit a final `.done(...)` from accumulated content (if not yet
  done) and finish.
- Otherwise decode as `OpenAIStreamChunk` and yield `.chunk(content)`
  for non-empty deltas.
- When the chunk includes `usage` (final chunk with `include_usage`),
  emit `.done(LLMChatResult(content: accumulated, model: chunk.model ?? model, promptTokens: usage.prompt_tokens, completionTokens: usage.completion_tokens))` and finish.

Selection context handling: same `includeSelectionContext` semantic
as Ollama. Append `"\n\nSelection:\n\(text)"` to the user message
content when `true`.

System prompt: prepend a `{"role":"system","content":"..."}` message
when `systemPrompt` is non-nil.

OpenAI does not natively support image payloads through this path;
for `.image(...)` payloads the body uses the `messages[].content`
array form with `image_url` items. v1 keeps image support OPTIONAL
— if image payload arrives, fall back to text prompt only (skip the
image) and emit a normal text-only request.

### `AnthropicClient.swift` (new)

```swift
struct AnthropicClient: LLMClient {
    var provider: AgentProvider { .anthropic }
    var endpoint: String
    var token: String

    func listModels() async throws -> [String] {
        // Anthropic does not expose a public list-models endpoint.
        // Return a hardcoded curated list for v1:
        // ["claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
    }

    func chatStream(...) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        // POST /messages stream:true
        // Headers:
        //   x-api-key: <token>
        //   anthropic-version: 2023-06-01
        //   content-type: application/json
        // Body: { "model":"...", "max_tokens":4096, "system":"...", "messages":[{"role":"user","content":"..."}], "stream":true }
        // Response: SSE
        //   event: message_start
        //   data: {"type":"message_start","message":{...}}
        //   event: content_block_delta
        //   data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}
        //   event: message_delta
        //   data: {"type":"message_delta","delta":{},"usage":{"input_tokens":..., "output_tokens":...}}
        //   event: message_stop
        //   data: {"type":"message_stop"}
    }
}
```

Anthropic streaming uses dual-line SSE (`event: ...\ndata: ...`).
Implementation:
- Use `URLSession.bytes(for:)` `.lines`.
- Track an `eventName` state. On a line beginning `event: `, set
  `eventName = ...`.
- On a `data: ` line, parse JSON.
- For `content_block_delta` with `delta.type == "text_delta"`, yield
  `.chunk(delta.text)`.
- For `message_delta` with `usage`, capture totals.
- For `message_stop`, emit `.done(...)`.

`max_tokens` defaults to 4096; not exposed in Settings v1.

### `GeminiClient.swift` (new)

```swift
struct GeminiClient: LLMClient {
    var provider: AgentProvider { .gemini }
    var endpoint: String
    var token: String

    func listModels() async throws -> [String] {
        // GET /models?key=<token>
        // Response: { "models":[{"name":"models/gemini-2.5-flash", ...}, ...] }
        // Filter to models supporting "generateContent".
    }

    func chatStream(...) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        // POST /models/{model}:streamGenerateContent?alt=sse&key=<token>
        // Body: { "contents":[{"parts":[{"text":"..."}], "role":"user"}], "systemInstruction":{"parts":[{"text":"..."}]} }
        // Response: SSE
        //   data: {"candidates":[{"content":{"parts":[{"text":"..."}]}}], "usageMetadata":{"promptTokenCount":..., "candidatesTokenCount":...}}\n\n
        // Final chunk includes "finishReason":"STOP" in candidates.
    }
}
```

Token in URL query param (`?key=<token>`). NEVER log the full URL —
log only the path component (e.g. `"models/gemini-2.5-flash:streamGenerateContent"`).

System prompt path uses `systemInstruction.parts[].text`, NOT a role.

### `SettingsView.swift` change

The existing Agent Section keeps the structure. Two functional changes:

1. **Provider Picker** writes `settings.agentProvider`. The
   `didSet` in `AppSettings` reloads the token from Keychain and the
   `endpoint` getter re-reads from `endpoints[active]`. SwiftUI
   re-renders bindings automatically.
2. **Endpoint default suggestion**: when the user picks a provider
   for the first time (i.e. `endpoints[provider] == nil`), show
   `provider.defaultEndpoint` in the TextField but keep storage on
   first user edit. Implementation: the existing `endpoint` getter
   already falls back to `defaultEndpoint`, so the TextField shows
   the default without persisting. As soon as the user types, the
   setter writes into `endpoints[provider]`.
3. **Model picker**: continues using the active client's
   `listModels()` via the existing `refreshModels()` async helper.
   Update `refreshModels()` to instantiate the client via
   `LLMClientFactory.make(for: settings)` instead of hardcoding
   `OllamaClient(...)`.

The "Custom model" TextField behavior is unchanged.

The "API token" SecureField binding goes to `settings.apiToken`
which is the derived per-provider view. Switching provider populates
the field with that provider's saved token.

For providers where `requiresAPIKey == false` (`ollama`, `lmStudio`),
the API token row could be hidden, but for v1 keep it always visible
(allowing optional bearer auth on self-hosted Ollama / LM Studio
proxies). The placeholder text changes per provider:

```swift
SecureField(
    settings.agentProvider.requiresAPIKey ? "API token" : "API token (선택)",
    text: $settings.apiToken
)
```

### `PopupController.swift` change

Replace:

```swift
let client = OllamaClient(endpoint: endpoint, token: token)
let stream = client.chatStream(...)
```

with:

```swift
let client = LLMClientFactory.make(for: settings)
let stream = client.chatStream(
    model: model,
    prompt: prompt,
    payload: payloadCopy,
    includeSelectionContext: includeContext,
    systemPrompt: systemPrompt
)
```

The rest of the loop body (chunk accumulation, .done metadata
extraction) only references protocol types, so no further changes.

Update the metadata construction to use the new field names:

```swift
let metadata = ResponseMetadata(
    model: result.model,
    totalTokens: result.promptTokens + result.completionTokens
)
```

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. New files exist: `LLMClient.swift`, `LLMClientFactory.swift`,
   `OpenAIClient.swift`, `AnthropicClient.swift`, `GeminiClient.swift`.
3. `OllamaClient` adopts `LLMClient`. `LLMStreamEvent` /
   `LLMChatResult` replace the old `OllamaStreamEvent` /
   `OllamaChatResult` types. References in `PopupController` use
   the new names.
4. Settings → Agent Picker lists 5 providers: Ollama / LM Studio /
   OpenAI / Anthropic / Gemini.
5. Switching to OpenAI: Endpoint defaults to
   `https://api.openai.com/v1`. API token field empty until user
   types. Saving the token persists it to Keychain under account
   `"openai"`.
6. Switching back to Ollama: endpoint shows the previous Ollama
   endpoint (e.g. `http://localhost:11434`) and the Ollama token
   (if any). The OpenAI token is preserved in Keychain (not erased).
7. Model picker fetches the active provider's model list:
   - Ollama → `GET /api/tags`
   - LM Studio / OpenAI → `GET /models`
   - Anthropic → hardcoded 3 entries
   - Gemini → `GET /models?key=...`
8. Streaming works for each provider — verify with one real call
   per provider against a working API. UI shows progressive text
   exactly as Ollama streaming does.
9. Metadata caption (`model: ... · tokens: ...`) populates correctly
   for each provider using `promptTokens + completionTokens`.
10. Backward compat: launching after upgrade with a pre-existing
    Ollama endpoint + token shows correct values in the Ollama
    slot. Settings UI behaves identically for a user who never
    switches provider.
11. No log line includes API tokens, full URLs with key=, or user
    selection/response content.
12. `URLError(.cancelled)` and `CancellationError` remain silent
    across all providers.
13. ResponsePanel pin / fade / hover-out / Markdown / single-action-
    per-cycle behavior preserved across all providers.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: no new permissions.
- [ ] Permission revoked at runtime: no new path.
- [ ] Key window: no new panels.
- [ ] Z-order: no change.
- [ ] Animation anchor: no change.
- [ ] Mouse / key event routing: no change.
- [ ] Cancellation: all streams honor Task cancellation via the
      existing `AsyncThrowingStream.onTermination → URLSession task
      cancel` pattern.
- [ ] Resource cleanup: per-stream URLSession data tasks close on
      Task completion or cancellation.
- [ ] UserDefaults schema: ADDS `endpointsPerProvider` (Data, JSON
      `[String:String]`); LEGACY `endpoint` and `apiToken` keys
      migrated and removed on first launch.

## Out of Scope

- Image payload routing for non-Ollama providers — text-only for
  now.
- Cost / pricing display per provider — Phase 17.x follow-up.
- Streaming response saving to clipboard (Phase 18 idea).
- Multi-key Anthropic (e.g. project-scoped keys) — single token
  per provider for v1.
- "Test connection" button in Settings — Phase 17.x.
- Bedrock / Vertex / Azure OpenAI variants.
- Model search UI within the picker — manual `Custom model` field
  stays as the escape hatch.
