# Plan: Improve Scribe Prompts + Disable Mention Triggers for Compaction Messages

## Problem Statement
1. Scribe uses `@advisor` when summarizing, causing those advisors to respond again
2. Compaction messages may contain `@mentions` from the original conversation that trigger unwanted responses

## Solution: Two-Part Fix

### Part 1: Improve Scribe Prompts

Update all scribe prompts to clearly distinguish between **requesting** and **referencing**:

```
MENTION USAGE RULES FOR SCRIBE:

REQUESTING RESPONSE (use @):
- Use @advisor when you want that specific advisor to respond next
- Use @all when you want all advisors to respond
- Examples:
  ✓ "@financial and @tech - please clarify your proposals"
  ✓ "@all - final thoughts before we conclude?"

REFERENCING ADVISORS (do NOT use @):
- When summarizing what advisors already said, use plain names
- Options:
  - "Financial suggested event platforms"
  - "The tech advisor raised concerns"
  - "As growth put it..."
  - "[financial] recommended..." (brackets for clarity)

EXAMPLES - Good vs Bad:

BAD (triggers unwanted response):
"Great input from @financial and @growth. I see alignment on..."
→ This causes financial and growth to respond again!

GOOD (summarizes without triggering):
"Great input from financial and growth. I see alignment on..."
→ No triggers, just reporting

GOOD (explicitly requests):
"@financial and @growth - please clarify your points about..."
→ Only triggers when you actually want responses
```

### Part 2: Code Change - Compaction Messages Ignore Mentions

Update runtime logic to skip mention processing for compaction messages:

```ruby
# In conversation_runtime.rb or specific runtimes
def advisors_to_respond(message)
  # CRITICAL: Compaction messages never trigger responses
  # They are summaries, not requests
  return [] if message.compaction?
  
  # Existing logic for non-compaction messages
  return conversation.advisors.non_scribes if message.mentions_all? && (message.from_user? || message.from_scribe?)
  return [] unless message.mentions.any? && (message.from_user? || message.from_scribe?)
  conversation.advisors.where(name: message.mentions)
end
```

Or in `message_resolved`:

```ruby
def message_resolved(message)
  return handle_compaction_complete(message) if message.compaction?
  
  # Skip normal resolution flow for compaction messages
  # They don't trigger advisor fanout
  return if message.compaction?
  
  # ... rest of existing logic
end
```

## Files to Modify

### Prompts
- `app/libs/ai/prompts/conversations/consensus_moderator.erb`
- `app/libs/ai/prompts/conversations/brainstorming_moderator.erb`
- Any other scribe-related prompts

### Code
- `app/libs/ai/runtimes/conversation_runtime.rb` - Add compaction check
- `app/libs/ai/runtimes/consensus_conversation_runtime.rb` - Verify inheritance
- `app/libs/ai/runtimes/brainstorming_conversation_runtime.rb` - Verify inheritance

## Implementation Details

### Prompt Template Section

Add this to the top of each scribe prompt:

```erb
<%# Scribe Mention Guidelines %>
<% if scribe? %>
CRITICAL - MENTION USAGE:
- Use @advisor ONLY when requesting a response
- DO NOT use @ when summarizing/referencing prior input
- Reference examples:
  ✗ "@financial suggested..." (WRONG - triggers response)
  ✓ "Financial suggested..." (CORRECT - just referencing)
<% end %>
```

### Code Implementation

In `ConversationRuntime#advisors_to_respond`:

```ruby
def advisors_to_respond(message)
  # Compaction messages are summaries, never requests
  return [] if message.compaction?
  
  # Rest of existing logic unchanged
  return conversation.advisors.non_scribes if message.mentions_all? && (message.from_user? || message.from_scribe?)
  return [] unless message.mentions.any? && (message.from_user? || message.from_scribe?)
  conversation.advisors.where(name: message.mentions)
end
```

Or as a guard in the individual runtime implementations:

```ruby
# In ConsensusConversationRuntime
def message_resolved(message)
  return handle_compaction_complete(message) if message.compaction?
  return unless message.from_scribe?
  
  # Compaction messages don't trigger normal scribe flow
  return if message.compaction?
  
  # ... rest of existing logic
end
```

## Testing

1. Create test: Scribe summarizes with @mentions → verify no advisor placeholders created
2. Create test: Compaction message contains @mentions → verify no triggers
3. Create test: User message with @mentions → verify normal triggering still works
4. Regression test: @all from scribe still triggers all advisors

## Pros

1. **Simple** - Minimal code change (just add `return [] if message.compaction?`)
2. **Backward compatible** - Existing behavior preserved for non-compaction messages
3. **Clear** - Prompt instructions make scribe behavior explicit
4. **Safe** - Compaction can never accidentally trigger advisor cascade

## Cons

1. **Still relies on scribe compliance** - May need monitoring
2. **Compaction content visible** - Users see @mentions in compacted text (cosmetic only)
3. **Not 100% foolproof** - Scribe could still use @ inappropriately in non-compaction messages

## Alternative Enhancement

If scribe compliance remains an issue, add post-processing:

```ruby
# Strip @ from scribe compaction messages before saving
def clean_compaction_content(content)
  content.gsub(/@([a-z0-9-]+)/, '\1')  # Remove @ but keep name
end
```

This would actively sanitize scribe output.

## Decision

**Pending user approval** to implement:
1. Scribe prompt updates with mention guidelines
2. Code change: compaction messages skip mention processing
