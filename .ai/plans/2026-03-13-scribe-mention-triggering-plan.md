# Plan: Prevent Scribe Mentions from Triggering Unwanted Advisor Responses

## Problem Statement
When the scribe summarizes or reports on advisor input, using `@advisor` syntax triggers those advisors to respond again. For example:
- Scribe says: "Great input from @financial and @growth..."
- This causes financial and growth advisors to respond again
- Also appears in compaction summaries, perpetuating the issue

## Root Cause
The `advisors_to_respond` method in runtimes treats all `@mentions` equally, regardless of whether they're:
- **Requests** ("@financial please respond") 
- **References** ("@financial suggested venues")

## Solution Options

### Option 1: Explicit Scribe Instruction
Add clear rules to scribe prompts about mention usage:

```
MENTION USAGE RULES:
- Use @advisor ONLY when you want that advisor to respond next
- When reporting/summarizing what advisors said, use:
  - Passive form: "The financial advisor suggested..."
  - Name in quotes: "As 'financial' put it..."
  - Descriptive: "The technical expert pointed out..."
  
EXAMPLES:
✓ "@financial @tech - please respond to this question" (requests response)
✗ "@financial suggested venues" (triggers unwanted response)
✓ "Financial suggested venues" (just reporting)
```

**Pros:** Simple, no code changes
**Cons:** Relies on model following instructions

### Option 2: Structured Scribe Output
Modify scribe prompt to separate references from requests:

```
OUTPUT FORMAT:
Summary: [Your summary text using passive voice for references]
Requesting response from: [@advisor1 @advisor2] (only include if you want responses)
```

Update runtime to only parse mentions from the "Requesting response" line.

**Pros:** Very explicit, machine-parseable
**Cons:** Requires runtime changes, more rigid format

### Option 3: Different Reference Syntax
Create non-triggering reference format:

- `@advisor` = requests response (existing behavior)
- `[advisor]` or `{advisor}` = just referencing (new)

Update prompts:
```
When summarizing advisor input, use [advisor_name] format:
  [financial] suggested event platforms
  [tech] raised concerns about integration
```

Update `Message#mentions` to only match `@` pattern.

**Pros:** Clean separation of concerns
**Cons:** Requires both prompt and code changes

### Option 4: Few-Shot Examples
Add concrete examples to scribe prompts:

```
GOOD - Summarizing without triggering:
"So far we have input from financial (event platforms) and tech (integration concerns)."

BAD - Accidentally triggers:
"So far @financial suggested event platforms and @tech raised concerns."

GOOD - Requesting specific advisors:
"@financial and @tech - please expand on your proposals"
```

**Pros:** Models learn from examples well
**Cons:** Takes up prompt tokens, still relies on model compliance

## Recommended Approach: Option 1 + 3

Combine explicit instruction with alternative syntax. This provides:
1. Clear guidance on when to use `@` vs alternatives
2. A fallback mechanism (`[advisor]` syntax) if model struggles with passive voice
3. No runtime changes needed for Option 1
4. Optional runtime change later if Option 3 syntax adoption is needed

## Implementation Steps

1. **Update scribe prompts** (`consensus_moderator`, `brainstorming_moderator`, etc.)
   - Add "MENTION USAGE RULES" section
   - Include examples of good vs bad usage
   - Add few-shot examples

2. **Test with real conversations**
   - Monitor for accidental triggers
   - Check if scribe uses passive voice correctly
   - If issues persist, implement Option 3 syntax

3. **Future: Optional runtime enhancement**
   - If Option 3 needed, update `Message#mentions` regex to exclude `[]` syntax
   - Update compaction prompt to also use `[]` syntax for references

## Files to Modify

- `app/libs/ai/prompts/agents/consensus_moderator.erb`
- `app/libs/ai/prompts/agents/brainstorming_moderator.erb`
- `app/libs/ai/prompts/agents/open_moderator.erb` (if exists)
- Optionally: `app/models/message.rb` (for Option 3 syntax)

## Success Criteria

- Scribe can summarize advisor input without triggering new responses
- Compaction summaries don't include @mentions that trigger advisors
- Advisors only respond when explicitly requested (by user or scribe @all)

## Decision

**Pending user approval** - Awaiting decision on which option(s) to implement.
