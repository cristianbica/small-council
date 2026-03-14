# Plan: Conversation Response Schema with Structured Output

## Problem Statement
When the scribe summarizes or reports on advisor input, using `@advisor` syntax triggers those advisors to respond again. The scribe needs a way to:
- Reference advisors in content without triggering them
- Explicitly request responses only when intended

## Proposed Solution: Structured Response Schema

Create a JSON schema that separates **content** from **delegation/requests**:

```json
{
  "content": "String - The text to display in chat",
  "request_responses_from": ["array of advisor names to notify"],
  "mention_all": "boolean - if true, notify all non-scribe advisors"
}
```

## Schema Definition

```ruby
class ConversationResponseSchema < AI::Schemas::BaseSchema
  attribute :content, Types::String
  attribute :request_responses_from, Types::Array.of(Types::String).default([])
  attribute :mention_all, Types::Bool.default(false)
  
  def advisors_to_notify(conversation)
    return conversation.advisors.non_scribes if mention_all
    return [] if request_responses_from.empty?
    conversation.advisors.where(name: request_responses_from)
  end
end
```

## How It Works

### Scribe Prompt Changes

Replace current mention-based guidance with structured output instructions:

```
OUTPUT FORMAT (JSON):
{
  "content": "Your message text here. When referencing advisors, use their plain name: 'financial suggested...' or 'the tech advisor noted...'",
  "request_responses_from": ["financial", "tech"],
  "mention_all": false
}

RULES:
- In "content", use plain advisor names without @: "financial", "tech", "growth"
- Only add names to "request_responses_from" if you want them to respond next
- Use "mention_all": true instead of listing all advisors individually

EXAMPLES:

Reporting status (no triggers):
{
  "content": "So far financial suggested event platforms and tech raised integration concerns.",
  "request_responses_from": [],
  "mention_all": false
}

Requesting specific advisors:
{
  "content": "Financial and tech, please expand on your proposals with more detail.",
  "request_responses_from": ["financial", "tech"],
  "mention_all": false
}

Requesting all advisors:
{
  "content": "All advisors, please share your perspectives on the integration timeline.",
  "request_responses_from": [],
  "mention_all": true
}
```

### Runtime Changes

Update `ConversationResponseHandler`:

```ruby
def handle(result)
  if result.is_a?(ConversationResponseSchema)
    # Structured output - separate content from delegation
    message = create_message(content: result.content)
    schedule_advisor_responses(result.advisors_to_notify(conversation))
  else
    # Legacy text output with @mentions
    message = create_message(content: result.content)
    schedule_advisor_responses(parse_mentions(result.content))
  end
end
```

## Pros

1. **Explicit separation** - No ambiguity between reference and request
2. **Machine-parseable** - No regex, no guessing
3. **Validatable** - Can lint that scribe isn't accidentally triggering
4. **Forward-compatible** - Easy to add more fields later (e.g., `next_round`, `summary_only`)
5. **Cleaner compaction** - Compacted summaries can also use schema to avoid triggering

## Cons

1. **More complex** - Requires schema definition and runtime changes
2. **Model compliance** - Still relies on model outputting valid JSON
3. **Migration** - Need to update all scribe prompts
4. **Fallback needed** - Should still support text output for error cases

## Implementation Plan

### Phase 1: Schema Definition
1. Create `ConversationResponseSchema` class
2. Add `advisors_to_notify` helper method
3. Unit tests for schema

### Phase 2: Handler Updates
1. Modify `ConversationResponseHandler` to check for schema
2. Handle both structured and legacy text outputs
3. Update tests

### Phase 3: Prompt Updates
1. Update `consensus_moderator` prompt with schema instructions
2. Update `brainstorming_moderator` prompt
3. Add few-shot examples showing JSON output

### Phase 4: Testing
1. Test scribe produces valid schema output
2. Test delegation works correctly
3. Test legacy text output still works (backward compat)

## Alternative: Hybrid Approach

Keep text output for display, but use metadata for delegation:

```ruby
{
  "content": "So far @financial and @growth have contributed...",
  "metadata": {
    "request_responses_from": []
  }
}
```

**Display:** "So far @financial and @growth have contributed..."
**Delegation:** None (empty array)

This lets scribe use `@` in text for readability, but explicitly controls who gets notified.

## Recommendation

Implement **structured schema with hybrid approach**:
- Scribe outputs JSON with `content` (can include `@` for display) + `request_responses_from` array
- UI renders content with @ highlighting
- Runtime uses `request_responses_from` for actual notifications
- No accidental triggers from content text

## Decision

**Pending user approval** - Awaiting decision on:
1. Pure structured schema (no @ in content)
2. Hybrid schema (@ in content, separate delegation array)
3. Keep current text-based approach with prompt improvements
