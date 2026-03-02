# RubyLLM::Agent Evaluation (Scribe)

## Goal

Evaluate whether RubyLLM::Agent provides a cleaner, reusable way to configure Scribe (instructions/tools/params) versus today’s per-call `RubyLLM.chat` setup.

## Sources

- https://rubyllm.com/agents/
- https://rubyllm.com/agentic-workflows/

## Summary of RubyLLM::Agent

RubyLLM::Agent is a class-based wrapper around the same configuration done via `RubyLLM.chat` and `Chat#with_*` calls. It centralizes model, instructions, tools, params, headers, schema, etc., and can be used either:

- **Plain Ruby mode**: `AgentClass.chat` → `RubyLLM::Chat`
- **Rails-backed mode**: `AgentClass.create!/find` when `chat_model` is set

Agents also support:

- **Runtime context** via blocks/lambdas (lazy evaluation)
- **Prompt conventions** in `app/prompts/<agent_name>/instructions.txt.erb`
- **Delegated chat methods** (ask/complete, tools, messages, event handlers)

## Fit for Scribe

**Potential benefits**

- Centralized configuration for Scribe instructions/tools/model/params
- Cleaner reuse across jobs/services (no repeated `with_*` calls)
- Prompt file conventions could standardize Scribe system prompts
- Runtime context blocks can inject dynamic values (space, council, user)

**Potential concerns**

- We already use a custom AI stack with per-account model selection and tool adapters
- Rails-backed agent mode expects a `chat_model` (not obviously aligned with our Conversation/Message structure)
- Migration requires re‑threading context/tool wiring into agent lifecycle

## Key Questions

1. Can Agent configuration coexist with our per-account model resolution and tool adapter layer?
2. Do we want to adopt prompt file conventions (`app/prompts/...`) for Scribe?
3. Would agent instances reduce complexity in `AI::Client` or just move it?
4. Is Rails-backed `chat_model` useful for our Conversation/Message design, or should we stay in plain Ruby mode?

## Recommendation (Current)

**Short‑term:** Treat RubyLLM::Agent as a **configuration wrapper** for Scribe (plain Ruby mode) if we want to centralize prompts/tools. This can be additive without touching storage models.

**Not recommended yet:** Rails-backed agent mode, since our “chat” persistence model doesn’t map cleanly to a single chat record, and we already manage conversation state.

## Next Steps (if pursued)

1. Create a small prototype `ScribeAgent < RubyLLM::Agent` in a spike branch (no prod change).
2. Use plain Ruby mode, inject tools + instructions via class macros.
3. Compare current `AI::Client` usage vs agent instance for parity (tools, params, event handlers).
4. Decide whether prompt files (`app/prompts/scribe_agent/...`) are desired for maintainability.
