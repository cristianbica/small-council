# Plan: Prevent and strip `[speaker: ...]` response prefixes

Type: bug
Scope: prompt instruction + output sanitization

## Goal
Stop advisors/models from prefixing responses with labels like `[speaker: business-marketing-strategist]`, and strip that prefix server-side if still produced.

## Changes
1. Prompt instruction:
   - Add explicit hard rule in `AI::Client#build_tool_policy_context_message`:
     - Do not prefix responses with `[speaker: ...]` or any speaker label.
     - Start directly with the answer content.
2. Server-side fallback sanitization:
   - In `GenerateAdvisorResponseJob`, normalize response content before saving:
     - Remove leading repeated `[speaker: ...]` labels at the start of the response.
     - Keep content unchanged otherwise.
3. Tests:
   - Add/update job tests in `test/jobs/generate_advisor_response_job_test.rb` for prefix stripping behavior.

## Out of scope
- Changing historical saved messages
- Prompt format changes for conversation history encoding

## Verification
- Run: `bin/rails test test/jobs/generate_advisor_response_job_test.rb`
- Run: `bin/rails test test/ai/unit/client_test.rb`
