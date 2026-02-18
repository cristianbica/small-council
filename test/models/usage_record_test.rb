require "test_helper"

class UsageRecordTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-usage")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    @conversation = @account.conversations.create!(council: @council, user: @user, title: "Test Conversation")
  end

  # Validation tests
  test "valid with required attributes" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25
    )
    assert usage_record.valid?
  end

  test "invalid without account" do
    ActsAsTenant.without_tenant do
      usage_record = UsageRecord.new(
        provider: "openai",
        model: "gpt-4",
        input_tokens: 100,
        output_tokens: 50,
        cost_cents: 25
      )
      assert_not usage_record.valid?
      assert_includes usage_record.errors[:account], "can't be blank"
    end
  end

  test "invalid without provider" do
    usage_record = @account.usage_records.new(
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25
    )
    assert_not usage_record.valid?
    assert_includes usage_record.errors[:provider], "can't be blank"
  end

  test "invalid without model" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25
    )
    assert_not usage_record.valid?
    assert_includes usage_record.errors[:model], "can't be blank"
  end

  test "invalid with negative input_tokens" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: -1,
      output_tokens: 50,
      cost_cents: 25
    )
    assert_not usage_record.valid?
    assert_includes usage_record.errors[:input_tokens], "must be greater than or equal to 0"
  end

  test "invalid with negative output_tokens" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: -1,
      cost_cents: 25
    )
    assert_not usage_record.valid?
    assert_includes usage_record.errors[:output_tokens], "must be greater than or equal to 0"
  end

  test "invalid with negative cost_cents" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: -1
    )
    assert_not usage_record.valid?
    assert_includes usage_record.errors[:cost_cents], "must be greater than or equal to 0"
  end

  test "input_tokens must be an integer" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 1.5,
      output_tokens: 50,
      cost_cents: 25
    )
    assert_not usage_record.valid?
    assert_includes usage_record.errors[:input_tokens], "must be an integer"
  end

  test "output_tokens must be an integer" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 1.5,
      cost_cents: 25
    )
    assert_not usage_record.valid?
    assert_includes usage_record.errors[:output_tokens], "must be an integer"
  end

  test "cost_cents must be an integer" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 1.5
    )
    assert_not usage_record.valid?
    assert_includes usage_record.errors[:cost_cents], "must be an integer"
  end

  test "valid with zero values" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 0,
      output_tokens: 0,
      cost_cents: 0
    )
    assert usage_record.valid?
  end

  # Association tests
  test "belongs to account" do
    usage_record = UsageRecord.new
    assert_respond_to usage_record, :account
  end

  test "belongs to message as optional" do
    usage_record = UsageRecord.new
    assert_respond_to usage_record, :message
  end

  test "valid without message" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25
    )
    assert usage_record.valid?
  end

  test "valid with message" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test message"
    )
    usage_record = @account.usage_records.new(
      message: message,
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25
    )
    assert usage_record.valid?
  end

  test "message association returns correct message" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test message"
    )
    usage_record = @account.usage_records.create!(
      message: message,
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25
    )
    assert_equal message, usage_record.message
  end

  # Scope tests
  test "by_provider scope filters by provider" do
    @account.usage_records.create!(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25
    )
    @account.usage_records.create!(
      provider: "anthropic",
      model: "claude-3",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 30
    )

    openai_records = UsageRecord.by_provider("openai")
    assert_equal 1, openai_records.count
    assert_equal "openai", openai_records.first.provider
  end

  test "by_model scope filters by model" do
    @account.usage_records.create!(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25
    )
    @account.usage_records.create!(
      provider: "openai",
      model: "gpt-3.5",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 10
    )

    gpt4_records = UsageRecord.by_model("gpt-4")
    assert_equal 1, gpt4_records.count
    assert_equal "gpt-4", gpt4_records.first.model
  end

  test "recorded_since scope returns records after time" do
    old_record = @account.usage_records.create!(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25,
      recorded_at: 2.days.ago
    )
    new_record = @account.usage_records.create!(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25,
      recorded_at: 1.hour.ago
    )

    recent = UsageRecord.recorded_since(1.day.ago)
    assert_not_includes recent, old_record
    assert_includes recent, new_record
  end

  test "recorded_before scope returns records before time" do
    old_record = @account.usage_records.create!(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25,
      recorded_at: 2.days.ago
    )
    new_record = @account.usage_records.create!(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25,
      recorded_at: 1.hour.ago
    )

    older = UsageRecord.recorded_before(1.day.ago)
    assert_includes older, old_record
    assert_not_includes older, new_record
  end

  # Custom method tests
  test "total_tokens returns sum of input and output tokens" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 25
    )
    assert_equal 150, usage_record.total_tokens
  end

  test "total_tokens with zero values" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 0,
      output_tokens: 0,
      cost_cents: 0
    )
    assert_equal 0, usage_record.total_tokens
  end

  test "cost_dollars returns cost in dollars" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 250
    )
    assert_equal 2.50, usage_record.cost_dollars
  end

  test "cost_dollars with zero cost" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 0
    )
    assert_equal 0.0, usage_record.cost_dollars
  end

  test "cost_dollars with fractional cents" do
    usage_record = @account.usage_records.new(
      provider: "openai",
      model: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      cost_cents: 1
    )
    assert_equal 0.01, usage_record.cost_dollars
  end

  # Default value tests
  test "input_tokens defaults to 0" do
    usage_record = @account.usage_records.create!(
      provider: "openai",
      model: "gpt-4"
    )
    assert_equal 0, usage_record.input_tokens
  end

  test "output_tokens defaults to 0" do
    usage_record = @account.usage_records.create!(
      provider: "openai",
      model: "gpt-4"
    )
    assert_equal 0, usage_record.output_tokens
  end

  test "cost_cents defaults to 0" do
    usage_record = @account.usage_records.create!(
      provider: "openai",
      model: "gpt-4"
    )
    assert_equal 0, usage_record.cost_cents
  end
end
