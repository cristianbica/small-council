# Pattern: Testing

## General conventions

- Prefer small, deterministic tests.
- Add coverage for regressions when fixing bugs.
- Keep tests close to the behavior they validate.
- Parallelization threshold is 50: files with < 50 tests run in a single process.

## Test setup

```ruby
def setup
  @account = accounts(:one)
  set_tenant(@account)           # sets ActsAsTenant.current_tenant
end
```

For integration/controller tests, also set the host:

```ruby
def setup
  @account = accounts(:one)
  host! "#{@account.slug}.example.com"
end
```

## Current user

`Current.user` is delegated from `Current.session`. To stub the current user in unit tests:

```ruby
Current.session = stub(user: @user)
```

Do NOT use `Current.user = @user` directly — there is no setter.

## Mocking AI::Client

`AI::Client` is **instance-based** — stub `.new` to return a mock client, then stub `.chat` on the mock:

```ruby
# Correct — mock the instance
mock_response = AI::Model::Response.new(content: "Response", usage: AI::Model::TokenUsage.new(input: 10, output: 20))
mock_client = mock("AI::Client")
mock_client.stubs(:chat).returns(mock_response)
AI::Client.stubs(:new).returns(mock_client)

# For provider-level class methods (test_connection, list_models):
AI::Client.stubs(:test_connection).returns({ success: true, model: "gpt-4o-mini" })
AI::Client.stubs(:list_models).returns([{ id: "gpt-4", name: "GPT-4" }])

# Wrong — do not stub class methods for instance usage
AI::Client.stubs(:generate_response).returns(...)  # No such class method
```

## Fixtures

Fixtures live in `test/fixtures/`. Key fixtures:
- `accounts(:one)` — primary test account (slug: `test-account`)
- `accounts(:two)` — secondary test account
- `spaces(:one)` etc. — spaces for `accounts(:one)`
- `memories(:one)` etc.

Fixtures do NOT include providers/llm_models — create these in test setup if needed.

## LLM model availability

`Space#create_scribe_advisor` and similar callbacks require an LLM model. If your test creates a Space or calls `scribe_advisor`, ensure the account has a model:

```ruby
provider = @account.providers.create!(name: "Test", provider_type: "openai", api_key: "key")
model = provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4", enabled: true)
```

## Test file locations

| Type | Location |
|------|----------|
| Model tests | `test/models/` |
| Controller tests | `test/controllers/` |
| Integration tests | `test/integration/` |
| Job tests | `test/jobs/` |
| Service tests | `test/services/` |
| Helper tests | `test/helpers/` |
| AI unit tests | `test/ai/unit/` |
| AI integration tests | `test/ai/integration/` (includes mock pattern examples) |
| System tests | `test/system/` (require Chrome, skip in CI without browser) |

Current suite: ~1396 runs, 96.79% line coverage, 85.38% branch coverage.
