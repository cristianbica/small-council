# Meeting and conversation context from memories

## Goal
Give advisors useful memory context for both council meetings and regular conversations, without changing lifecycle triggers.

## Non-goals
- No UI redesign.
- No semantic search/reranker infrastructure.
- No change to memory authoring/versioning UX.

## Evidence summary (read-only investigation)

### 1) How a meeting/conversation starts and where advisor responses are generated
- Start UI/form: `app/views/conversations/new.html.erb` (`Start Meeting`, `Initial Message`).
- Conversation creation path:
  - `app/controllers/conversations_controller.rb`
  - `create` dispatches to `create_council_meeting` or `create_adhoc_conversation`.
  - Both creation methods persist the initial user message via `@conversation.messages.create!`.
- Response generation path for normal message posts:
  - `app/controllers/messages_controller.rb#create` saves a user message.
  - Then `ConversationLifecycle.new(@conversation).user_posted_message(@message)` is called.
  - `app/services/conversation_lifecycle.rb#create_pending_message_and_enqueue` creates pending placeholders and enqueues `GenerateAdvisorResponseJob.perform_later`.
  - `app/jobs/generate_advisor_response_job.rb#perform` calls `AI::ContentGenerator#generate_advisor_response` (or scribe follow-up path) and updates placeholder content.
- Product intent clarification:
  - Expected UX is to start a council meeting with a topic and continue by asking questions in chat.
  - Therefore, meeting-start lifecycle parity is not required for this task.

### 2) Where memory data exists and how it is fetched/used
- Primary memory model:
  - `app/models/memory.rb` (types, scopes, active/archived, source links, versioning hooks).
  - `MEMORY_TYPES`: `summary`, `conversation_summary`, `conversation_notes`, `knowledge`.
  - `Memory.primary_summary_for(space)` returns latest active `summary` memory.
  - `Memory.create_conversation_summary!` used at conclusion.
- Versioning:
  - `app/models/memory_version.rb`.
- CRUD/search/export UI/API:
  - `app/controllers/memories_controller.rb` and routes in `config/routes.rb` under `/spaces/:space_id/memories`.
- Memory creation from concluded conversations:
  - `app/jobs/generate_conversation_summary_job.rb#create_conversation_memory` creates `conversation_summary` memory linked to conversation.
- AI context building:
  - `app/libs/ai/context_builders/base_context_builder.rb` fetches `recent_memories` and `primary_summary`.
  - `app/libs/ai/context_builders/conversation_context_builder.rb` includes `memories` and `primary_summary` in context hash.
- AI tool-based memory access:
  - `app/libs/ai/tools/internal/query_memories_tool.rb`
  - `app/libs/ai/tools/internal/list_memories_tool.rb`
  - `app/libs/ai/tools/internal/read_memory_tool.rb`
- Critical behavior detail:
  - `AI::Client#chat` (`app/libs/ai/client.rb`) applies only `system_prompt` and chat messages directly; the `context` hash is assigned to tool adapters (`adapter.context = context`) for tool execution.
  - `app/libs/ai/adapters/ruby_llm_tool_adapter.rb` passes that context into tool execution only.
  - So memories in context builder are available to tools and recorder context, but are not explicitly serialized into the prompt/messages by default.

### 3) Best insertion points for memory context
- Insertion point A (prompt context, best place for deterministic injection):
  - `app/libs/ai/content_generator.rb#generate_advisor_response`
  - After building context with `ConversationContextBuilder`, explicitly compose memory context text and prepend/merge into system instructions or an additional system message.
- Insertion point B (centralized context formatting helper):
  - `app/libs/ai/context_builders/conversation_context_builder.rb` and/or a new helper in `base_context_builder.rb`.
  - Replace raw `memories: recent_memories` usage for model-facing context with deterministic “memory index block” fields derived from selected memory types.
  - Keep full memory objects available for tools, but provide a compact preformatted index for model input.
- Insertion point C (client-level RubyLLM input wiring):
  - `app/libs/ai/client.rb#chat`
  - Add an explicit context serialization path so curated memory index is sent to RubyLLM as model-visible context (system/additional message), not only tool adapter context.

## Strategy options

### Option 1: Add explicit memory index block to advisor prompt (keep current triggers)
What changes:
- In `AI::ContentGenerator#generate_advisor_response`, inject a compact structured memory index as explicit system context:
  - Primary summary memory (full or capped excerpt).
  - Knowledge memories: `id`, `title`, first 50 words of summary.

Pros:
- Directly addresses “advisors have little context” for meetings and conversations.
- Deterministic grounding while preserving tool-based deep fetch.

Cons:
- Token growth and possible latency/cost increase.
- Needs careful caps to avoid prompt bloat.

Complexity:
- Medium.

Risks:
- Overweighting stale/low-quality memories if selection is naive.

### Option 2: Context-only enrichment with strict budgeting (recommended)
What changes:
- Keep lifecycle behavior unchanged.
- Adjust `ConversationContextBuilder` to publish curated memory index data for model consumption (while retaining tool context data).
- Use `AI::Client` to serialize/send that memory index to RubyLLM as explicit model-visible context.
- Add memory index block for all advisor turns (both meetings and conversations), with strict item and word limits.
- Instruct advisors: use memory IDs to call read/query tools when details are needed.

Pros:
- Aligns with desired UX (no forced meeting-start responses).
- Improves grounding in every turn, not only first turn.
- Keeps costs predictable with deterministic caps.

Cons:
- Requires tuning caps and ordering heuristics.

Complexity:
- Medium.

Risks:
- If caps are too tight, advisors may miss useful memories.
- If caps are too loose, prompts may get expensive.

## Recommendation
Choose Option 2 (context-only enrichment with strict budgeting), with this exact memory index shape:
1. Include active primary `summary` memory at top (single block).
2. Include knowledge memory index entries:
  - fields: `id`, `title`, `summary_excerpt_50_words`.
3. Add instruction line: “If more detail is needed, fetch by memory id using memory tools.”

## Minimal rollout plan
1. Adjust context builder output:
  - In `ConversationContextBuilder`, keep `memories` for tool/runtime usage.
  - Add a curated model-facing field (e.g., `memory_index`) containing:
    - primary summary,
    - knowledge entries (`id`, `title`, `summary_excerpt_50_words`).
2. Add AI client serialization path for model-visible context:
  - Extend `AI::Client#chat` to accept/send optional context messages derived from `context[:memory_index]`.
  - Ensure this serialized block is appended as a system/context message to RubyLLM before conversation messages.
3. Wire generation flow:
  - `AI::ContentGenerator#generate_advisor_response` passes curated `memory_index` through context so `AI::Client` can serialize it.
4. Apply deterministic limits (suggested defaults):
  - Knowledge memories: max 8.
  - Excerpt size: first 50 words normalized.
5. Skip archived/inactive memories and keep existing tools unchanged.
6. Observe + tune:
  - Log selected memory IDs and prompt block size for advisor turns.

## Verification approach
- Unit tests:
  - `ConversationContextBuilder` outputs expected `memory_index` shape and capped excerpts.
  - `AI::Client` includes serialized memory index message in RubyLLM request assembly path.
  - `AI::ContentGenerator` includes memory index block with expected sections.
  - Excerpts are capped to 50 words.
  - IDs/titles are present for knowledge entries.
  - Memory limits and ordering rules are respected.
- Job/service tests:
  - `GenerateAdvisorResponseJob` path receives expected memory index context.
- Integration test:
  - Post a user message in both a meeting and an adhoc conversation, assert payload/system context contains memory index sections.
- Non-regression:
  - Existing message post flow (`MessagesController#create`) unchanged.

## Scope assumptions and unknowns
- Assumption: memory index should be available in both meeting and adhoc conversation advisor turns.
- Unknown: final RubyLLM best-practice for long contextual blocks (`with_instructions` append vs additional system message), to be validated in implementation while preserving deterministic serialization.

## Doc impact
- deferred (implementation not started).
