# Plan: Advisor payload attribution + council context system prompt

## Goal
Reduce cross-advisor bias and attribution loss by making prompt context explicit and speaker-aware.

Target payload contract for advisor responses:
1. advisor system prompt
2. new council/advisor context system prompt
3. memory index system prompt
4. full conversation messages with speaker-prefixed content

## Non-goals
- No change to advisor selection logic (mentions/@all/RoE targeting) in this plan.
- No round-snapshot/deterministic orchestration refactor in this plan.
- No UI redesign; payload/protocol change only.

## Scope + assumptions
- Scope: `AI::ContentGenerator`, `AI::Client`, and related tests.
- Applies to normal advisor responses and scribe follow-up responses unless explicitly excluded.
- “Speaker-prefixed” means every outbound conversation message content is transformed to include an unambiguous speaker label before being sent to RubyLLM/provider.
- Existing role mapping remains (`advisor` -> `assistant`).

## Feedback on requested approach
- This is a strong low-risk first step: it addresses the verified metadata drop (`sender_name` not forwarded) without large architecture changes.
- Adding council/advisor context as a dedicated system prompt improves role separation and reduces ambiguous multi-assistant history.
- It will not fully remove same-round race effects (later jobs still may see earlier responses), but it materially improves attribution and instruction clarity.

## Implementation plan (non-code)
1. **Introduce a dedicated council context system prompt builder**
   - Add a formatter that builds concise system text containing:
     - council purpose/description (or fallback if absent)
     - participant advisors and roles (advisor/scribe)
     - current responder identity and expected role perspective
     - RoE mode summary (open/consensus/brainstorming)
   - Ensure it avoids verbose duplication and remains deterministic.

2. **Add council context prompt into payload in explicit order**
   - In `AI::Client#chat`, keep existing `with_instructions(system_prompt)` as item #1.
   - Insert new council context prompt as an explicit `system` message before memory index.
   - Keep memory index insertion as the next `system` message.
   - Document and test this exact ordering.

3. **Prefix outbound conversation messages with speaker labels**
   - Transform each outbound message content to include speaker identity, e.g. `"[speaker: <name>] <content>"`.
   - Apply for both roots and replies; preserve chronological ordering.
   - Keep placeholder filtering unchanged (`is thinking...` pending placeholders excluded).
   - Ensure labels are available even when sender display name is missing (stable fallback).

4. **Keep compatibility with existing tool/context paths**
   - Do not remove existing context hash fields yet.
   - Do not change message persistence format in DB; only outbound payload transformation.

5. **Add/adjust tests**
   - `test/ai/unit/client_test.rb`
     - verifies payload system-message order:
       1) advisor instructions
       2) council/advisor context system message
       3) memory index system message
       4) conversation messages
   - `test/ai/unit/content_generator_test.rb`
     - verifies speaker-prefixed outbound message content includes distinct advisor/user identities.
   - `test/ai/unit/context_builders/conversation_context_builder_test.rb` (or adjacent unit tests)
     - verifies council/advisor role context includes expected participants/roles.

## Acceptance criteria
- Advisor-response payload always includes both system prompts (advisor + council context) before memory index.
- Memory index remains included after the council context prompt when available.
- All outbound conversation messages include speaker labels in sent content.
- Existing placeholder filtering behavior remains intact.
- Unit tests cover ordering and speaker-prefix behavior.

## Risks
- **Token growth risk:** prefixed content + added system prompt increases input tokens.
  - Mitigation: keep council prompt compact and avoid repeating long descriptions.
- **Prompt conflict risk:** multiple system-level instructions may conflict.
  - Mitigation: make council context descriptive (facts/roles), not normative over advisor system prompt.
- **Backward expectation risk in tests/recordings:** request payload snapshots may change.
  - Mitigation: update assertions to validate order/semantics, not brittle full-string matches.

## Verification plan
- Focused tests:
  - `bin/rails test test/ai/unit/client_test.rb`
  - `bin/rails test test/ai/unit/content_generator_test.rb`
  - `bin/rails test test/ai/unit/context_builders/conversation_context_builder_test.rb`
- Optional confidence pass:
  - `bin/rails test test/services/conversation_lifecycle_test.rb`

## Deferred follow-up (separate plan)
- Deterministic same-round snapshotting to remove race-based cross-advisor influence.
- Optional RoE-specific visibility policy (e.g., stricter isolation in open mode).

## Handoff
- Next workflow: `change` (`bug`)
- Implementation owner: Builder (after explicit approval)
- `doc impact`: update relevant AI/conversation docs after implementation
