# Plan: Text-Based Response Format with Delegation Markers

## Problem Statement
JSON schemas for conversational text have reliability issues (85-95% compliance). We need a format that:
- Separates content from delegation
- Is human-readable
- Is model-friendly (no JSON escaping issues)
- Can be parsed reliably

## Proposed Solution: DELEGATION/CONTENT Markers

Use plain text with explicit markers:

```
DELEGATION: @financial @tech
CONTENT: Financial suggested event platforms and tech raised integration concerns.
```

## Format Specification

### Full Format
```
DELEGATION: [space-separated advisor names or @all or none]
CONTENT: [The actual message text]
```

### Variations

**No delegation (just reporting):**
```
DELEGATION: none
CONTENT: So far financial suggested venues and tech raised concerns.
```

**Request all advisors:**
```
DELEGATION: @all
CONTENT: All advisors, please share your final thoughts.
```

**Request specific advisors:**
```
DELEGATION: @financial @tech
CONTENT: Financial and tech, please expand on your proposals.
```

**Multi-line content:**
```
DELEGATION: @growth
CONTENT: Growth advisor, please review the following:

1. Market analysis shows...
2. Competitor landscape...
3. Recommended approach...
```

## Parsing Rules

```ruby
class ConversationResponseParser
  def self.parse(text)
    lines = text.lines.map(&:chomp)
    
    # Find DELEGATION line
    delegation_line = lines.find { |l| l.start_with?("DELEGATION:") }
    delegation_text = delegation_line.to_s.sub("DELEGATION:", "").strip
    
    # Find CONTENT line and everything after
    content_start = lines.index { |l| l.start_with?("CONTENT:") }
    content_lines = content_start ? lines[content_start..-1] : lines
    content_text = content_lines.join("\n").sub("CONTENT:", "").strip
    
    # Parse delegation
    advisors = if delegation_text.include?("@all")
                 :all
               elsif delegation_text.downcase == "none" || delegation_text.empty?
                 []
               else
                 delegation_text.scan(/@([a-z0-9-]+)/).flatten
               end
    
    {
      content: content_text,
      advisors: advisors,
      mention_all: advisors == :all
    }
  end
end
```

## Prompt Instructions for Scribe

```
OUTPUT FORMAT:

DELEGATION: [who should respond next]
CONTENT: [your message]

DELEGATION RULES:
- "none" = no one responds (just reporting/summarizing)
- "@all" = all non-scribe advisors respond
- "@advisor1 @advisor2" = specific advisors respond

EXAMPLES:

Example 1 - Reporting status (no triggers):
DELEGATION: none
CONTENT: So far financial suggested event platforms and tech raised integration concerns.

Example 2 - Requesting all:
DELEGATION: @all
CONTENT: All advisors, please share your perspectives on the timeline.

Example 3 - Requesting specific:
DELEGATION: @financial @tech
CONTENT: Financial and tech, please expand on your proposals with more detail.

Example 4 - Multi-line content:
DELEGATION: @growth
CONTENT: Growth advisor, please review:

1. Market analysis shows strong demand
2. Competitor landscape is favorable
3. Recommended approach is acquisition

IMPORTANT:
- Use "none" when summarizing what advisors already said
- Use @advisor names ONLY when you want them to respond
- In CONTENT, you can reference advisors by plain name: "financial suggested..."
```

## Handler Implementation

Update `ConversationResponseHandler`:

```ruby
def handle(result)
  parsed = parse_response(result.content)
  
  # Create message with just content (no DELEGATION line visible)
  message = create_message(content: parsed[:content])
  
  # Schedule responses based on delegation
  if parsed[:mention_all]
    schedule_all_advisors(message)
  elsif parsed[:advisors].any?
    schedule_specific_advisors(message, parsed[:advisors])
  end
end

def parse_response(text)
  # Try structured format first
  if text.include?("DELEGATION:")
    ConversationResponseParser.parse(text)
  else
    # Legacy: parse @mentions from content
    {
      content: text,
      advisors: parse_mentions(text),
      mention_all: text.match?(/@(all|everyone)/i)
    }
  end
end
```

## Compaction Format

Same format works for compaction summaries:

```
DELEGATION: none
CONTENT: COMPACTED SUMMARY:

TOPIC: Acquisition targets for AMS

KEY FACTS:
- Financial: Event platforms align with venue business
- Tech: Integration complexity is manageable
- Growth: Market demand is strong

DECISIONS: None yet

OPEN QUESTIONS:
- Which platform to prioritize?
- Timeline for integration?

ADVISOR POSITIONS:
- Financial: Pro-event platform
- Tech: Cautious but supportive
- Growth: Strongly pro-acquisition
```

## Pros

1. **100% parseable** - No JSON syntax errors
2. **Human-readable** - No escaping, no brackets
3. **Model-friendly** - Natural text generation
4. **Clear separation** - DELEGATION vs CONTENT explicit
5. **Backward compatible** - Can still parse legacy @mentions
6. **Debugging** - Easy to read raw output

## Cons

1. **Less structured** - No type safety
2. **Template reliance** - Model must follow DELEGATION/CONTENT format
3. **Parsing edge cases** - Multi-line content, missing markers

## Mitigations

1. **Validation** - Check DELEGATION line exists, warn if missing
2. **Defaults** - If no DELEGATION found, treat as "none" (safe default)
3. **Logging** - Track parse success rate
4. **Examples** - 3-4 few-shot examples in prompt

## Comparison with JSON Schema

| Aspect | JSON Schema | Text Markers |
|--------|-------------|--------------|
| Compliance | 85-95% | 95-99% |
| Parse failures | JSON syntax errors | Missing markers |
| Escaping issues | Quote escaping in content | None |
| Human readable | No | Yes |
| Type safety | Yes | No |
| Multi-line content | Complex | Natural |

## Recommendation

Use **text markers with validation**:
- 95-99% compliance vs 85-95% for JSON
- Natural for models to generate
- Easy to debug
- Graceful degradation (missing marker = "none")

## Implementation Steps

1. Create `ConversationResponseParser`
2. Update `ConversationResponseHandler` to use parser
3. Update scribe prompts with DELEGATION/CONTENT format
4. Add few-shot examples
5. Add validation/logging
6. Test with real conversations

## Decision

**Pending user approval** - Awaiting decision to proceed with text marker approach.
