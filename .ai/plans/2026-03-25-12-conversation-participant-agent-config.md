# Plan: Per-Participant Advisor Model + Tool Configuration

## Intake Summary
- Type: feature
- Goal: let users configure model selection and allowed tools per advisor participant within a conversation, then reflect that configuration in header chips and runtime execution.
- Constraints:
  - Persist on conversation_participants and keep tenant/account invariants intact.
  - Preserve existing behavior for all existing participants unless user explicitly changes config.
  - Reuse existing Turbo frame modal pattern (page-modal) and DaisyUI/Tailwind component style.
  - Keep scope focused to conversation participant configuration, chip UX, and runtime override wiring.

## Acceptance Criteria Checklist
- [ ] Conversation participants can store a per-participant model override and allowed-tool override.
- [ ] Existing conversation_participants rows remain behaviorally unchanged after migration.
- [ ] Conversation header advisor chips are visually larger and show model text truncation with full model name tooltip.
- [ ] Advisor chips show tool icon(s) plus a numeric tool count badge.
- [ ] Hovering advisor chips reveals a tooltip listing all allowed tools for that participant.
- [ ] Clicking an advisor chip opens a modal for that participant’s model/tool configuration.
- [ ] Modal shows tools grouped by category and allows toggling each tool allowed/not allowed.
- [ ] Saving modal updates conversation_participants and refreshes chip UI without a full page reload.
- [ ] Runtime uses participant model/tool overrides when present, and falls back to current advisor defaults when absent.
- [ ] Targeted model/controller/integration/runtime tests cover persistence, UI rendering signals, and override behavior.

## Non-Goals
- Redesigning advisor creation/edit pages.
- Introducing provider/model management changes outside participant-level selection.
- Adding new AI tools beyond the existing registry.

## Assumptions + Open Questions (max 3)
1. Assumption: Scribe participant is configurable through the same chip/modal flow unless product wants it locked.
2. Open question: Should an explicitly empty tool selection mean no tools, while nil means inherit defaults? Plan assumes yes to preserve backward compatibility.
3. Open question: If a selected participant model later becomes disabled/deleted, should runtime hard-fail or silently fall back to advisor/account default? Plan assumes fallback + validation on save.

## Impacted Files and Components
- Data/model:
  - app/models/conversation_participant.rb
  - app/models/conversation.rb
  - db/migrate/*_add_agent_config_to_conversation_participants.rb (new)
  - db/schema.rb
- Routing/controllers:
  - config/routes.rb
  - app/controllers/conversations_controller.rb (or a new nested participant config controller)
- Views/UI:
  - app/views/conversations/_participant_badges.html.erb
  - app/views/conversations/_chat.html.erb
  - app/views/conversations/show.html.erb
  - app/views/conversations/*participant*_modal*.erb (new partial for config modal)
- Runtime/tool integration:
  - app/libs/ai/contexts/conversation_context.rb
  - app/libs/ai/agents/advisor_agent.rb
  - app/libs/ai/tasks/base_task.rb
  - app/libs/ai/runtimes/conversation_runtime.rb
  - app/libs/ai/runtimes/open_conversation_runtime.rb
  - app/libs/ai/runtimes/consensus_conversation_runtime.rb
  - app/libs/ai/runtimes/brainstorming_conversation_runtime.rb
  - app/libs/ai.rb
  - app/libs/ai/tools/abstract_tool.rb
- JS behavior:
  - app/javascript/controllers/page_modal_controller.js (reuse)
  - app/javascript/controllers/*participant*_controller.js (new only if needed for richer chip behavior)
- Tests:
  - test/models/conversation_participant_test.rb
  - test/controllers/conversations_controller_comprehensive_test.rb (or new participant-config controller test)
  - test/integration/conversation_flow_test.rb or test/integration/complete_conversation_flows_test.rb
  - test/libs/ai/contexts/conversation_context_test.rb
  - test/libs/ai/runtimes/conversation_runtime_test.rb
  - test/libs/ai/agents/advisor_agent_test.rb

## Data Model and Migration Strategy
1. Add participant-level config columns on conversation_participants:
- llm_model_id: bigint, nullable, foreign key to llm_models.
- allowed_tool_refs: jsonb, nullable (array semantics in model layer).

2. Default strategy for existing rows:
- llm_model_id = nil for all existing/new rows unless user sets override.
- allowed_tool_refs = nil for all existing/new rows unless user sets override.
- Nil means inherit current advisor-agent defaults, preserving today’s runtime behavior exactly.

3. Validation/invariants in model:
- llm_model_id, when present, must belong to participant account (and ideally be enabled at selection time).
- allowed_tool_refs, when present, must be an array of unique known tool refs from AI::Tools::AbstractTool::REGISTRY keys.
- Canonicalize allowed_tool_refs (strip blanks, unique, stable order) before validation.

4. Derived behavior helpers in model:
- effective_llm_model(conversation/account fallback chain).
- effective_tool_refs(defaults_from_agent_or_role).
- tools_configured? and model_configured? convenience predicates for UI badges.

## Backend Flow
1. Routing
- Add participant-config endpoints scoped by conversation, for example:
  - GET conversation participant config modal content.
  - PATCH conversation participant config update.
- Keep route space/conversation scoping aligned with existing Current.space lookup patterns.

2. Controller actions
- Load conversation via Current.space.conversations.find.
- Load participant via conversation.conversation_participants.find.
- Authorize with existing conversation management rule (same guard used for finish/archive/delete) to avoid privilege drift.
- GET renders modal frame partial for page-modal.
- PATCH updates participant config and responds:
  - turbo_stream: replace conversation-participants + close/replace page-modal.
  - html fallback: redirect to conversation with notice/alert.

3. Strong params
- Permit only llm_model_id and allowed_tool_refs: [] (plus optional inherit toggles if chosen).
- Never permit account_id/conversation_id/advisor_id/role edits from this flow.

4. Error handling
- Validation failures re-render modal with inline errors in turbo_frame.
- Invalid/missing participant returns 404 within conversation scope.

## UI Flow
1. Chip rendering updates
- Make advisor chips larger and button-like for click affordance.
- Keep avatar + advisor name.
- Add model sublabel with truncation and title tooltip containing full model name.
- Add tool icon cluster and a tool count badge.
- Add hover tooltip listing all allowed tools for the participant (full list, one-per-line).

2. Tooltip behavior
- Use accessible hover/focus tooltips (title or Daisy tooltip pattern) that also work via keyboard focus.
- For empty tool list, show explicit No tools allowed text.
- For inherited default tools, show effective tool list and optionally a Defaults label.

3. Modal behavior
- Clicking a chip opens a page-modal Turbo frame dialog.
- Modal contains:
  - Participant identity (name/avatar).
  - Model selector from Current.account.llm_models.enabled.
  - Tools grouped by category derived from tool ref namespace prefix (memories, advisors, conversations, internet, other).
  - Per-tool toggle checkbox.
  - Save and cancel actions.
- On save success, chip row refreshes immediately.

4. Mobile and density
- Preserve wrapping behavior in participant chip row.
- Ensure truncation widths and tooltip interactions are usable on small screens.

## AI Runtime Integration
1. Override resolution order
- Model resolution:
  - participant llm_model override (if present)
  - advisor effective_llm_model
  - account default_llm_model
  - first enabled account model
- Tool resolution:
  - participant allowed_tool_refs override (including explicit empty array)
  - agent defaults (current behavior)

2. Wiring points
- Extend AI.generate_advisor_response to accept participant-specific tool override payload.
- In conversation runtime request_advisor_response, locate the participant for message.sender and pass override data into task/context.
- Update AI::Contexts::ConversationContext to use participant override model when present.
- Keep AdvisorAgent default logic intact for inheritance path; only bypass with explicit override input.

3. Compaction safeguard
- Update compaction weakest-model calculation to consider participant effective model overrides, not only advisor defaults.

## Test Plan
1. Model tests
- conversation_participant: validates model/account matching, validates known tool refs, canonicalizes refs, and computes effective override/fallback methods.

2. Controller/request tests
- participant config endpoints:
  - successful update (turbo + html fallback)
  - invalid llm_model_id/tool refs rejected
  - unauthorized user blocked
  - conversation/participant scoping enforced

3. View/integration tests
- participant chip rendering includes:
  - truncated model display and full-model tooltip attribute
  - tool count badge
  - tooltip tool list text
  - chip link/button target to modal frame
- modal render contains grouped tool sections and toggle controls.

4. Runtime/context tests
- conversation_context picks participant override model first.
- runtime forwards participant tool override to AI task path.
- compaction threshold uses weakest effective participant model.
- inheritance path still matches previous behavior when overrides are nil.

## Verification Commands
1. bin/rails db:migrate
2. bin/rails test test/models/conversation_participant_test.rb
3. bin/rails test test/libs/ai/contexts/conversation_context_test.rb
4. bin/rails test test/libs/ai/runtimes/conversation_runtime_test.rb
5. bin/rails test test/libs/ai/agents/advisor_agent_test.rb
6. bin/rails test test/controllers/conversations_controller_comprehensive_test.rb
7. bin/rails test test/integration/conversation_flow_test.rb

## Rollout and Risk Notes
- Data safety: nullable override columns avoid forced backfill and preserve behavior for all existing rows.
- Runtime risk: participant lookup on every response can add query overhead; mitigate with eager loading or memoized lookup per runtime cycle.
- UX risk: dense chip content may wrap aggressively; validate with realistic advisor counts and mobile viewport.
- Product risk: ambiguity between inherited defaults and explicit empty tools; surface this clearly in modal copy.

## Doc Impact
- updated
- Update feature docs after implementation:
  - .ai/docs/features/conversations.md
  - .ai/docs/features/data-model.md
  - .ai/docs/patterns/tool-system.md
  - .ai/docs/patterns/ui-components.md
