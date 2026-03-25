# Plan: Add Anthropic Provider Support

## Change type
feature

## Goal
Add Anthropic as a first-class provider in the single-page provider setup flow, connection testing, and model listing.

## Scope
- In scope:
  - Add `anthropic` to supported provider types.
  - Add Anthropic provider card on add-provider page.
  - Add dedicated Anthropic provider form partial (separate partial, no conditional mega-form).
  - Wire frame partial selection to Anthropic.
  - Update AI provider configuration to use Anthropic API key.
  - Extend tests for provider enum, single-page flow, and connection tester coverage.
  - Update provider docs to list Anthropic and new setup option.
- Out of scope:
  - Changes to existing provider edit behavior.
  - New Anthropic-specific advanced settings beyond API key.

## Implementation
1. Model + controller wiring
- Update `Provider` enum to include `anthropic`.
- Update `ProvidersController#provider_form_partial` to return Anthropic partial.
- Keep `normalize_provider_type` behavior as-is (it already checks enum keys).

2. New-page provider selection UI
- Add Anthropic card link in `providers/new` next to OpenAI/OpenRouter.
- Add Anthropic branch in `providers/_provider_form_frame`.

3. Anthropic form partial
- Create `providers/_new_form_anthropic.html.erb`.
- Fields: name, api_key, enabled, status block, test button, disabled create button.
- Keep `data-turbo-frame="_top"` for create submit to avoid frame redirect issues.

4. AI client integration
- Extend `AI::Client.configure_provider` with `when "anthropic"` and set `config.anthropic_api_key = provider.api_key`.
- Leave other providers unchanged.

5. Tests
- Update model tests:
  - enum includes `anthropic`
  - predicate `type_anthropic?` behavior
- Update single-page integration tests:
  - Anthropic card visible
  - Anthropic frame form loads and excludes organization_id
- Update provider connection tester tests:
  - success and failure test cases for provider_type `anthropic`

6. Docs
- Update `.ai/docs/features/providers.md` supported providers table and setup notes.

## Verification
- `bin/rails test test/models/provider_test.rb`
- `bin/rails test test/services/provider_connection_tester_test.rb`
- `bin/rails test test/integration/providers_single_page_test.rb`
- `bin/rails test test/controllers/providers_controller_test.rb`

## Risks and mitigations
- Risk: RubyLLM config key name mismatch for Anthropic.
- Mitigation: implement with `config.anthropic_api_key` and validate via tests/stubs; if runtime mismatch appears, adjust quickly with a focused follow-up.
