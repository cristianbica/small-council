# Refresh Context Audit (2026-03-11)

Scope: `.ai/docs/**`, `.ai/MEMORY.md`, and migration notes only.

## Inventory decisions

### `.ai/` docs
- Keep + update: `.ai/docs/overview.md`
- Keep + update: `.ai/docs/features/README.md`
- Keep + update: `.ai/docs/patterns/README.md`
- Keep + update: `.ai/docs/features/conversation-system.md`
- Keep + update: `.ai/docs/features/conversations.md`
- Keep + update: `.ai/docs/features/ai-integration.md`
- Keep + update: `.ai/MEMORY.md`
- Keep (no changes needed): remaining feature/pattern docs not showing drift in this pass

### Legacy/orchestration docs outside `.ai`
- Keep: `AGENTS.md` (global pointer to canonical `.ai/` workflows)
- Keep: `.github/copilot-instructions.md` (wrapper that points to `.ai/`)
- Keep: `.opencode/AGENTS.md` (wrapper; same canonical source)
- Keep: `.github/agents/*.agent.md` wrappers (thin wrappers around canonical `.ai/agents/*`)
- Archive: none required in this pass (no conflicting legacy rule set found)
- Delete: none in this pass

## Drift detected

- Conversation docs referenced removed/older auto-title path (`GenerateConversationTitleJob` + `tasks/conversation_title`).
- Conversation system doc still described migration-only RoE mapping and deleted service files as active migration context.
- `.ai/MEMORY.md` command section was stale (older test counts and no current lint status).

## Critical additions introduced

- Feature doc: conversation title lifecycle and state transitions.
- Pattern doc: `Current.account`/`Current.space` and `acts_as_tenant` scoping pattern.
