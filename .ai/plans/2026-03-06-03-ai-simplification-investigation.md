# Investigation: Simplify AI Interaction Architecture

Date: 2026-03-06

## 1. Intent

- Question to answer:
  - How should Small Council simplify its AI architecture across runtime flow, tool wiring, prompts, commands, jobs, and persistence, while staying compatible with the current app shape and taking advantage of RubyLLM-native concepts where they actually reduce custom glue?
- Success criteria:
  - Map the current end-to-end AI interaction surfaces with concrete evidence.
  - Identify the highest-value simplification seams, including whether slash commands can be removed.
  - Propose 2-4 viable architectural options, recommend one, and define a phased handoff to a later `change` workflow.

## 2. Scope + constraints

- In scope:
  - Conversation-time AI runtime and orchestration.
  - Tool inventory, grouping, and adapter/wiring shape.
  - Prompt/instruction assembly and duplication.
  - Jobs, controllers, models, and persistence directly tied to model interactions.
  - Secondary AI surfaces for title generation, advisor prompt generation, and council description generation.
- Out of scope:
  - Implementing the refactor.
  - UI redesign beyond noting affected surfaces.
  - Provider/model admin flow except where it constrains the runtime architecture.
- Read-only default acknowledged: yes
- Instrumentation/spikes allowed (explicit permission): no
- Timebox: 60 minutes

## 3. Evidence collected

- Files inspected:
  - [.ai/docs/features/ai-integration.md](.ai/docs/features/ai-integration.md)
  - [.ai/docs/features/model-interactions.md](.ai/docs/features/model-interactions.md)
  - [.ai/docs/features/conversations.md](.ai/docs/features/conversations.md)
  - [.ai/docs/features/conversation-system.md](.ai/docs/features/conversation-system.md)
  - [.ai/docs/features/council-management-tools.md](.ai/docs/features/council-management-tools.md)
  - [.ai/docs/patterns/tool-system.md](.ai/docs/patterns/tool-system.md)
  - [.ai/docs/patterns/command-pattern.md](.ai/docs/patterns/command-pattern.md)
  - [.ai/docs/patterns/architecture.md](.ai/docs/patterns/architecture.md)
  - [.ai/plans/2026-03-06-02-ruby-llm-tool-approval-investigation.md](.ai/plans/2026-03-06-02-ruby-llm-tool-approval-investigation.md)
  - [app/controllers/messages_controller.rb](app/controllers/messages_controller.rb)
  - [app/controllers/conversations_controller.rb](app/controllers/conversations_controller.rb)
  - [app/controllers/advisors_controller.rb](app/controllers/advisors_controller.rb)
  - [app/controllers/councils_controller.rb](app/controllers/councils_controller.rb)
  - [app/services/conversation_lifecycle.rb](app/services/conversation_lifecycle.rb)
  - [app/services/command_parser.rb](app/services/command_parser.rb)
  - [app/services/commands/base_command.rb](app/services/commands/base_command.rb)
  - [app/services/commands/invite_command.rb](app/services/commands/invite_command.rb)
  - [app/jobs/generate_advisor_response_job.rb](app/jobs/generate_advisor_response_job.rb)
  - [app/jobs/generate_conversation_title_job.rb](app/jobs/generate_conversation_title_job.rb)
  - [app/libs/ai/client.rb](app/libs/ai/client.rb)
  - [app/libs/ai/content_generator.rb](app/libs/ai/content_generator.rb)
  - [app/libs/ai/context_builders/base_context_builder.rb](app/libs/ai/context_builders/base_context_builder.rb)
  - [app/libs/ai/context_builders/conversation_context_builder.rb](app/libs/ai/context_builders/conversation_context_builder.rb)
  - [app/libs/ai/adapters/ruby_llm_tool_adapter.rb](app/libs/ai/adapters/ruby_llm_tool_adapter.rb)
  - [app/libs/ai/model_interaction_recorder.rb](app/libs/ai/model_interaction_recorder.rb)
  - [app/libs/ai/tools/base_tool.rb](app/libs/ai/tools/base_tool.rb)
  - [app/libs/ai/tools/conversations/ask_advisor_tool.rb](app/libs/ai/tools/conversations/ask_advisor_tool.rb)
  - Representative internal tools under [app/libs/ai/tools/internal](app/libs/ai/tools/internal)
  - [app/models/space.rb](app/models/space.rb)
  - [app/models/advisor.rb](app/models/advisor.rb)
  - [app/models/conversation.rb](app/models/conversation.rb)
  - [app/models/message.rb](app/models/message.rb)
  - [app/models/memory.rb](app/models/memory.rb)
  - [app/models/model_interaction.rb](app/models/model_interaction.rb)
  - [app/models/usage_record.rb](app/models/usage_record.rb)
  - [app/views/shared/_chat.html.erb](app/views/shared/_chat.html.erb)
  - [app/views/messages/_message.html.erb](app/views/messages/_message.html.erb)
  - [config/routes.rb](config/routes.rb)
- Commands run:
  - None. Investigation was read-only file inspection and workspace search.
- Observations:
  - Message posting enters at [app/controllers/messages_controller.rb#L6](app/controllers/messages_controller.rb#L6), then delegates to [app/services/conversation_lifecycle.rb#L11](app/services/conversation_lifecycle.rb#L11), which both parses slash commands and decides which advisors respond.
  - Advisor responses are generated asynchronously in [app/jobs/generate_advisor_response_job.rb#L1](app/jobs/generate_advisor_response_job.rb#L1), which delegates into [app/libs/ai/content_generator.rb#L161](app/libs/ai/content_generator.rb#L161) and [app/libs/ai/client.rb#L54](app/libs/ai/client.rb#L54).
  - The Scribe tool list is manually enumerated in [app/libs/ai/content_generator.rb#L317](app/libs/ai/content_generator.rb#L317).
  - Prompt/instruction logic is split across advisor system prompts, a hardcoded Scribe prompt in [app/models/space.rb#L32](app/models/space.rb#L32), content templates in [app/libs/ai/content_generator.rb#L35](app/libs/ai/content_generator.rb#L35), and runtime policy/system messages in [app/libs/ai/client.rb#L62](app/libs/ai/client.rb#L62), [app/libs/ai/client.rb#L67](app/libs/ai/client.rb#L67), and [app/libs/ai/client.rb#L438](app/libs/ai/client.rb#L438).
  - Slash commands are a narrow parallel path: the parser only registers `invite` in [app/services/command_parser.rb#L3](app/services/command_parser.rb#L3), and the app already has an explicit invite endpoint and UI in [app/controllers/conversations_controller.rb#L91](app/controllers/conversations_controller.rb#L91) and [app/views/shared/_chat.html.erb#L64](app/views/shared/_chat.html.erb#L64).
  - Persistence for AI activity is split between per-message model interactions in [app/models/model_interaction.rb#L1](app/models/model_interaction.rb#L1) and cost/usage records created inside [app/libs/ai/client.rb#L283](app/libs/ai/client.rb#L283).

## 4. Findings

### How it works today

1. A user posts a message through [app/controllers/messages_controller.rb#L6](app/controllers/messages_controller.rb#L6).
2. [app/services/conversation_lifecycle.rb#L11](app/services/conversation_lifecycle.rb#L11) resets Scribe counters, checks for slash commands at [app/services/conversation_lifecycle.rb#L19](app/services/conversation_lifecycle.rb#L19), parses mentions, creates placeholders, and enqueues the next advisor job at [app/services/conversation_lifecycle.rb#L237](app/services/conversation_lifecycle.rb#L237).
3. [app/jobs/generate_advisor_response_job.rb#L1](app/jobs/generate_advisor_response_job.rb#L1) marks the placeholder as responding, picks the generator path, and hands execution to [app/libs/ai/content_generator.rb#L161](app/libs/ai/content_generator.rb#L161) or [app/libs/ai/content_generator.rb#L192](app/libs/ai/content_generator.rb#L192).
4. [app/libs/ai/content_generator.rb#L288](app/libs/ai/content_generator.rb#L288) chooses a model, attaches a manual tool list from [app/libs/ai/content_generator.rb#L317](app/libs/ai/content_generator.rb#L317), builds conversation messages, and delegates to [app/libs/ai/client.rb#L54](app/libs/ai/client.rb#L54).
5. [app/libs/ai/client.rb#L181](app/libs/ai/client.rb#L181) builds a RubyLLM chat, adapts each tool via [app/libs/ai/adapters/ruby_llm_tool_adapter.rb#L13](app/libs/ai/adapters/ruby_llm_tool_adapter.rb#L13), injects multiple system messages, then executes the call.
6. The client records model interactions through RubyLLM event hooks at [app/libs/ai/client.rb#L217](app/libs/ai/client.rb#L217) and usage through [app/libs/ai/client.rb#L266](app/libs/ai/client.rb#L266).
7. The job persists the final content, then feeds control back into [app/services/conversation_lifecycle.rb#L67](app/services/conversation_lifecycle.rb#L67) for follow-up queueing and Scribe behavior.

### Top findings

1. The runtime boundary is too wide and responsibilities are smeared across four layers.
   - Conversation orchestration lives in [app/services/conversation_lifecycle.rb#L11](app/services/conversation_lifecycle.rb#L11).
   - Execution transport, prompt policy, usage tracking, and interaction recording live in [app/libs/ai/client.rb#L54](app/libs/ai/client.rb#L54).
   - Tool selection, message serialization, prompt templates, cache concerns, and model selection live in [app/libs/ai/content_generator.rb#L35](app/libs/ai/content_generator.rb#L35), [app/libs/ai/content_generator.rb#L288](app/libs/ai/content_generator.rb#L288), and [app/libs/ai/content_generator.rb#L317](app/libs/ai/content_generator.rb#L317).
   - Job-level lifecycle/error semantics live in [app/jobs/generate_advisor_response_job.rb#L1](app/jobs/generate_advisor_response_job.rb#L1).
   - Result: any behavior change around model interactions cuts across too many files.

2. Tool wiring is manual, Scribe-centric, and not expressed as reusable capabilities.
   - The Scribe gets a hardcoded list of 20 tools in [app/libs/ai/content_generator.rb#L317](app/libs/ai/content_generator.rb#L317).
   - There are 22 tool classes in the codebase, including [app/libs/ai/tools/conversations/ask_advisor_tool.rb#L8](app/libs/ai/tools/conversations/ask_advisor_tool.rb#L8), but that conversation tool is not wired.
   - The current abstraction is “a flat array of tool instances” rather than “capability packs” like memory-read, memory-write, conversation-read, council-admin, advisor-admin, or external-web.
   - This makes it hard to reason about what an agent can do and harder to swap in RubyLLM-native configuration later.

3. Prompt and instruction assembly is duplicated and partly contradictory.
   - The Scribe prompt still references `/invite` inside [app/models/space.rb#L48](app/models/space.rb#L48).
   - Runtime policy messages in [app/libs/ai/client.rb#L438](app/libs/ai/client.rb#L438) contain hard rules that are separate from advisor prompts and separate again from template prompts in [app/libs/ai/content_generator.rb#L35](app/libs/ai/content_generator.rb#L35).
   - Conversation messages are rewritten with `[speaker: ...]` labels in [app/libs/ai/content_generator.rb#L443](app/libs/ai/content_generator.rb#L443), while the runtime policy separately tells the model not to emit such labels in [app/libs/ai/client.rb#L461](app/libs/ai/client.rb#L461), and the job strips them again in [app/jobs/generate_advisor_response_job.rb#L127](app/jobs/generate_advisor_response_job.rb#L127).
   - This is a sign that message representation and instruction policy are coupled but not centrally owned.

4. Slash commands are now mostly redundant.
   - The only registered slash command is `invite` in [app/services/command_parser.rb#L3](app/services/command_parser.rb#L3).
   - The same capability already exists as a first-class controller/model path through [app/controllers/conversations_controller.rb#L91](app/controllers/conversations_controller.rb#L91) and [app/models/conversation.rb#L85](app/models/conversation.rb#L85).
   - The chat UI also exposes invite affordances directly in [app/views/shared/_chat.html.erb#L64](app/views/shared/_chat.html.erb#L64), yet still advertises `/invite` in [app/views/shared/_chat.html.erb#L172](app/views/shared/_chat.html.erb#L172) and [app/views/shared/_chat.html.erb#L193](app/views/shared/_chat.html.erb#L193).
   - Removing slash commands would delete a whole branch in [app/services/conversation_lifecycle.rb#L19](app/services/conversation_lifecycle.rb#L19) with limited product loss.

5. The context builder is broader than the runtime currently needs.
   - [app/libs/ai/context_builders/conversation_context_builder.rb#L31](app/libs/ai/context_builders/conversation_context_builder.rb#L31) assembles `memories`, `primary_summary`, `related_conversations`, `conversation_thread`, `advisors`, and `available_advisors`.
   - The client directly turns only council context, memory index, and current messages into model input in [app/libs/ai/client.rb#L62](app/libs/ai/client.rb#L62), [app/libs/ai/client.rb#L67](app/libs/ai/client.rb#L67), and [app/libs/ai/client.rb#L72](app/libs/ai/client.rb#L72).
   - This suggests the app lacks a narrower run-context contract and instead passes a bulky, loosely-typed hash around “just in case”.

6. Some AI surfaces appear partially dead or legacy.
   - `conversation_summary` and `memory_content` templates exist in [app/libs/ai/content_generator.rb#L70](app/libs/ai/content_generator.rb#L70) and [app/libs/ai/content_generator.rb#L112](app/libs/ai/content_generator.rb#L112), but no matching generation methods were found.
   - `message.prompt_text` is displayed in [app/views/messages/_message.html.erb#L39](app/views/messages/_message.html.erb#L39) and [app/views/messages/_message.html.erb#L93](app/views/messages/_message.html.erb#L93), and encrypted in [app/models/message.rb#L25](app/models/message.rb#L25), but no active write path was found during workspace search.
   - These are good candidates to either formalize or remove during simplification.

7. RubyLLM should replace glue selectively, not via a full rewrite.
   - The previous investigation in [.ai/plans/2026-03-06-02-ruby-llm-tool-approval-investigation.md#L72](.ai/plans/2026-03-06-02-ruby-llm-tool-approval-investigation.md#L72) confirms RubyLLM is strong on tool execution, callbacks, schema support, and continuation after tool calls, but not on app-specific orchestration or human approval semantics.
   - The best leverage is likely structured outputs for utility generations, capability-based tool registration, and event-hook-backed persistence, while keeping conversation/job orchestration app-owned.

- Confidence level: high for the current map and main simplification seams; medium for legacy/dead-surface conclusions because that part was inferred from file inspection and search only.

## 5. Options

### Option A: Local cleanup only

- Summary:
  - Remove slash commands, trim dead templates, and extract a few helper methods while keeping the current `ConversationLifecycle -> GenerateAdvisorResponseJob -> AI::ContentGenerator -> AI::Client` stack intact.
- Pros:
  - Lowest scope.
  - Fastest to deliver.
- Cons:
  - Preserves the current blurred boundaries.
  - Leaves prompt assembly and tool wiring largely manual.
  - Does not create a cleaner architecture for future AI changes.
- Assessment:
  - Worth doing only if the goal is immediate deletion of `/invite` and little else.

### Option B: Recommended: Introduce an AI run kernel with agent profiles and capability packs

- Summary:
  - Keep conversation orchestration in the app, but collapse AI execution into three explicit concepts:
    - `AI::RunContext` or equivalent typed context object for a single model interaction.
    - `AI::AgentProfile` definitions for Scribe, standard advisors, and utility generations.
    - `AI::CapabilityRegistry` that maps capability packs to RubyLLM tools and policies.
  - Keep `GenerateAdvisorResponseJob` as the async boundary, but make it call a single AI runtime entry point.
  - Move prompt/instruction assembly into profile objects so the client only executes.
  - Replace ad hoc JSON parsing for utility tasks with RubyLLM structured output or schema-driven helpers where supported.
- Pros:
  - Separates orchestration, prompt composition, tool capability, and transport cleanly.
  - Makes slash-command removal straightforward because invite logic remains a domain operation, not a text parser feature.
  - Creates a path to adopt more RubyLLM-native concepts without forking RubyLLM or overfitting the app to it.
  - Lets the Scribe become “an agent profile with capabilities” rather than “special case scattered across model, generator, and lifecycle”.
- Cons:
  - Medium refactor, not a one-file cleanup.
  - Requires careful migration around prompt and persistence behavior.
- Assessment:
  - Best fit for the repo and the user’s goals: simplify, decouple, drop slash commands, and be creative without an uncontrolled rewrite.

### Option C: RubyLLM-first rewrite around agents/tools/schemas

- Summary:
  - Push more behavior into RubyLLM-native abstractions, using library-level agent/tool composition as the primary architecture.
- Pros:
  - Attractive on paper.
  - Could shrink some adapter code.
- Cons:
  - The app still owns jobs, persistence, tenant context, and conversation turn-taking.
  - Risks replacing understandable Rails orchestration with opaque library glue.
  - Higher migration risk for limited payoff.
- Assessment:
  - Too aggressive as the first simplification pass.

### Option D: Collapse most actions into tool-driven Scribe behavior

- Summary:
  - Lean into Scribe as the main actor: remove commands, expose more domain actions as tools, and encourage natural-language requests over explicit UI/domain paths.
- Pros:
  - Creative and coherent if the product wants Scribe as the primary control plane.
  - Could reduce some controller branching over time.
- Cons:
  - Increases reliance on model behavior for actions that already have deterministic UI/domain flows.
  - More product-risky than necessary.
  - Harder to keep permission boundaries obvious.
- Assessment:
  - Good inspiration for selective use of tool-driven actions, but not a strong primary refactor target.

### Recommendation + rationale

- Recommendation:
  - Choose Option B.
- Rationale:
  - It simplifies the architecture at the correct seam: one runtime kernel, one context contract, one place for agent capabilities, and one place for prompt/instruction composition.
  - It preserves the healthy part of the current design, which is app-owned async orchestration and persistence.
  - It removes slash commands cleanly because they are already redundant.
  - It creates an upgrade path for RubyLLM-native structured outputs and tool configuration without rewriting the whole product around RubyLLM.

## 6. Recommended simplification architecture

### Target shape

1. Create a single AI runtime entry point.
   - Introduce a runtime service such as `AI::Runner` or `AI::Runtime` that becomes the only place jobs/controllers call for model execution.
   - Likely targets:
     - [app/libs/ai/client.rb](app/libs/ai/client.rb)
     - [app/libs/ai/content_generator.rb](app/libs/ai/content_generator.rb)
     - [app/jobs/generate_advisor_response_job.rb](app/jobs/generate_advisor_response_job.rb)

2. Replace the loose context hash with a typed run context.
   - Define a typed context object carrying `account`, `space`, `conversation`, `message`, `advisor`, `user`, `interaction_kind`, and any capability flags.
   - Context builders should build this narrower object, not a kitchen-sink hash.
   - Likely targets:
     - [app/libs/ai/context_builders/base_context_builder.rb](app/libs/ai/context_builders/base_context_builder.rb)
     - [app/libs/ai/context_builders/conversation_context_builder.rb](app/libs/ai/context_builders/conversation_context_builder.rb)

3. Replace manual tool arrays with capability packs.
   - Group tools into packs such as `memory_read`, `memory_write`, `conversation_read`, `advisor_admin`, `council_admin`, and `external_web`.
   - Agent profiles request packs; the registry resolves them to RubyLLM tool instances.
   - This makes “Scribe gets these capabilities” a declarative statement instead of a hardcoded array in one method.
   - Likely targets:
     - [app/libs/ai/content_generator.rb](app/libs/ai/content_generator.rb)
     - [app/libs/ai/tools/base_tool.rb](app/libs/ai/tools/base_tool.rb)
     - [app/libs/ai/tools](app/libs/ai/tools)

4. Move instructions into agent profiles.
   - Define explicit profiles for `scribe_conversation`, `advisor_conversation`, `scribe_followup`, `title_generator`, `advisor_profile_generator`, and `council_description_generator`.
   - Each profile owns base instructions, response style, structured output expectations, and capability packs.
   - The client should stop assembling policy from multiple places and instead execute a prepared profile/run request.
   - Likely targets:
     - [app/models/space.rb](app/models/space.rb)
     - [app/libs/ai/content_generator.rb](app/libs/ai/content_generator.rb)
     - [app/libs/ai/client.rb](app/libs/ai/client.rb)

5. Remove slash commands and treat invite as a domain action.
   - Delete the `/invite` parser/command path.
   - Keep `ConversationsController#invite_advisor` and `Conversation#add_advisor` as the deterministic invite surface.
   - Update Scribe instructions and chat hints so users rely on UI invite or natural language guidance, not slash syntax.
   - Likely targets:
     - [app/services/command_parser.rb](app/services/command_parser.rb)
     - [app/services/commands](app/services/commands)
     - [app/services/conversation_lifecycle.rb](app/services/conversation_lifecycle.rb)
     - [app/views/shared/_chat.html.erb](app/views/shared/_chat.html.erb)
     - [app/models/space.rb](app/models/space.rb)

6. Use RubyLLM structured output for utility generations.
   - Advisor profile generation, council description generation, and conversation title generation are better fits for structured output/schema paths than manual prompt-plus-JSON-cleanup.
   - This can shrink `parse_json_response` and reduce prompt fragility.
   - Likely targets:
     - [app/libs/ai/content_generator.rb](app/libs/ai/content_generator.rb)
     - [app/controllers/advisors_controller.rb](app/controllers/advisors_controller.rb)
     - [app/controllers/councils_controller.rb](app/controllers/councils_controller.rb)
     - [app/jobs/generate_conversation_title_job.rb](app/jobs/generate_conversation_title_job.rb)

7. Consolidate persistence hooks under the runtime.
   - Keep RubyLLM event hooks, but move all run recording policy under the runtime layer so `AI::Client` is transport-oriented instead of a transport-plus-auditing-plus-policy object.
   - Decide whether `message.prompt_text` should be formally written by the runtime or deleted as legacy UI/debug residue.
   - Likely targets:
     - [app/libs/ai/client.rb](app/libs/ai/client.rb)
     - [app/libs/ai/model_interaction_recorder.rb](app/libs/ai/model_interaction_recorder.rb)
     - [app/models/model_interaction.rb](app/models/model_interaction.rb)
     - [app/models/usage_record.rb](app/models/usage_record.rb)
     - [app/views/messages/_message.html.erb](app/views/messages/_message.html.erb)

## 7. Handoff

- Next workflow:
  - `change`
- Proposed phased scope:
  - Phase 1: remove slash commands and centralize invite as a domain/UI flow.
    - Delete parser and command classes.
    - Remove command branching from conversation lifecycle.
    - Update Scribe prompt and chat copy.
    - Verification ideas:
      - request/integration tests for invite via controller path
      - message posting flow without command parsing regression
  - Phase 2: introduce agent profiles and capability registry without changing tool behavior.
    - Move Scribe tool selection out of `AI::ContentGenerator#advisor_tools`.
    - Encode instruction assembly in profile objects.
    - Keep current runtime behavior stable.
    - Verification ideas:
      - existing job/unit tests for advisor response generation
      - targeted tests asserting tool capability sets by profile
  - Phase 3: introduce a unified runtime entry point and typed run context.
    - Reduce `AI::ContentGenerator` to thin profile-specific helpers or remove it entirely in favor of a new runtime layer.
    - Move persistence hooks behind the runtime.
    - Verification ideas:
      - job tests for success, API error, empty response, and Scribe follow-up
      - model interaction and usage record assertions
  - Phase 4: migrate utility generations to structured output and prune dead surfaces.
    - Replace manual JSON cleanup where RubyLLM schema support is adequate.
    - Decide fate of `conversation_summary`, `memory_content`, and `message.prompt_text`.
    - Verification ideas:
      - controller tests for advisor/council generation endpoints
      - title job tests

- Minimal viable first refactor slice:
  - Phase 1 plus the smallest part of Phase 2:
    - remove `/invite`
    - add a first version of `AI::CapabilityRegistry` for the current Scribe tool set
    - leave the rest of the runtime behavior unchanged
  - Why this slice:
    - It deletes a redundant code path immediately.
    - It creates the architectural seam needed for broader simplification without forcing a large migration all at once.

- Verification plan:
  - Run targeted tests around:
    - conversation/message flow
    - job execution
    - tool unit tests
    - generation endpoints
  - Likely commands:
    - `bin/rails test test/jobs/generate_advisor_response_job_test.rb`
    - `bin/rails test test/integration/complete_conversation_flows_test.rb`
    - `bin/rails test test/services/command_parser_test.rb test/services/commands_comprehensive_test.rb` before removal, then replace with invite-path coverage after removal
    - `bin/rails test test/ai/unit/client_test.rb test/ai/unit/model_interaction_recorder_test.rb`
    - `bin/rails test test/controllers` for advisor/council generation endpoints as needed

- Doc impact:
  - deferred
  - If the follow-on change is approved, update:
    - [.ai/docs/features/ai-integration.md](.ai/docs/features/ai-integration.md)
    - [.ai/docs/features/conversation-system.md](.ai/docs/features/conversation-system.md)
    - [.ai/docs/patterns/tool-system.md](.ai/docs/patterns/tool-system.md)
    - [.ai/docs/patterns/command-pattern.md](.ai/docs/patterns/command-pattern.md) or remove if commands are deleted

## 8. Open questions

- Should natural-language “invite X” requests remain purely UI/domain-driven, or should Scribe eventually be able to trigger the same domain action through a constrained tool?
  - Why it remains unknown:
    - This is a product boundary choice, not a code-discovery question.

- Does the team want to keep message-level prompt/debug display as a first-class feature, or can `prompt_text` and related legacy debug UI be removed?
  - Why it remains unknown:
    - The current write path was not found, so the feature may be legacy, but product intent is unclear.

- For utility generations, is RubyLLM structured output reliable enough across the enabled provider mix to replace the current prompt-plus-cleanup approach immediately, or should the app keep a fallback path?
  - Why it remains unknown:
    - This requires implementation-time provider verification, not read-only inspection.

Approve this plan?
