# frozen_string_literal: true

require "test_helper"

class ModelInteractionTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "Test Space")
    @provider = @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "test-key")
    @llm_model = @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4", enabled: true)
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    @conversation = @account.conversations.create!(council: @council, user: @user, title: "Test", space: @space)
    @message = @account.messages.create!(conversation: @conversation, sender: @user, role: "user", content: "Hello")
  end

  test "valid with required attributes" do
    interaction = ModelInteraction.new(
      account: @account,
      message: @message,
      sequence: 0,
      request_payload: { model: "gpt-4", messages: [] },
      model_identifier: "gpt-4",
      input_tokens: 100,
      output_tokens: 50,
      duration_ms: 123.4
    )
    assert interaction.valid?
  end

  test "requires account" do
    ActsAsTenant.without_tenant do
      interaction = ModelInteraction.new(
        message: @message,
        sequence: 0,
        request_payload: { model: "gpt-4" }
      )
      assert_not interaction.valid?
      assert_includes interaction.errors[:account], "can't be blank"
    end
  end

  test "requires message" do
    interaction = ModelInteraction.new(
      account: @account,
      sequence: 0,
      request_payload: { model: "gpt-4" }
    )
    assert_not interaction.valid?
    assert_includes interaction.errors[:message], "must exist"
  end

  test "requires sequence" do
    interaction = ModelInteraction.new(
      account: @account,
      message: @message,
      sequence: nil,
      request_payload: { model: "gpt-4" }
    )
    assert_not interaction.valid?
    assert_includes interaction.errors[:sequence], "can't be blank"
  end

  test "sequence must be non-negative integer" do
    interaction = ModelInteraction.new(
      account: @account,
      message: @message,
      sequence: -1,
      request_payload: { model: "gpt-4" }
    )
    assert_not interaction.valid?
    assert_includes interaction.errors[:sequence], "must be greater than or equal to 0"
  end

  test "sequence must be an integer" do
    interaction = ModelInteraction.new(
      account: @account,
      message: @message,
      sequence: 1.5,
      request_payload: { model: "gpt-4" }
    )
    assert_not interaction.valid?
    assert_includes interaction.errors[:sequence], "must be an integer"
  end

  test "requires request_payload" do
    interaction = ModelInteraction.new(
      account: @account,
      message: @message,
      sequence: 0,
      request_payload: nil
    )
    assert_not interaction.valid?
    assert_includes interaction.errors[:request_payload], "can't be blank"
  end

  test "chronological scope orders by sequence" do
    interaction_b = ModelInteraction.create!(
      account: @account, message: @message, sequence: 1,
      request_payload: { model: "gpt-4" }, model_identifier: "gpt-4"
    )
    interaction_a = ModelInteraction.create!(
      account: @account, message: @message, sequence: 0,
      request_payload: { model: "gpt-4" }, model_identifier: "gpt-4"
    )

    ordered = ModelInteraction.where(message: @message).chronological
    assert_equal [ interaction_a, interaction_b ], ordered.to_a
  end

  test "total_tokens sums input and output" do
    interaction = ModelInteraction.new(input_tokens: 100, output_tokens: 50)
    assert_equal 150, interaction.total_tokens
  end

  test "total_tokens with zero values" do
    interaction = ModelInteraction.new(input_tokens: 0, output_tokens: 0)
    assert_equal 0, interaction.total_tokens
  end

  test "belongs to message and destroying message destroys interactions" do
    interaction = ModelInteraction.create!(
      account: @account, message: @message, sequence: 0,
      request_payload: { model: "gpt-4" }, model_identifier: "gpt-4"
    )

    assert_difference "ModelInteraction.count", -1 do
      @message.destroy!
    end
  end

  test "tenant scoping works" do
    ModelInteraction.create!(
      account: @account, message: @message, sequence: 0,
      request_payload: { model: "gpt-4" }, model_identifier: "gpt-4"
    )

    other_account = Account.create!(name: "Other Account", slug: "other-account-mi")
    set_tenant(other_account)

    assert_equal 0, ModelInteraction.count

    # Restore tenant for teardown
    set_tenant(@account)
    assert_equal 1, ModelInteraction.count
  end

  test "default values for input_tokens and output_tokens" do
    interaction = ModelInteraction.create!(
      account: @account, message: @message, sequence: 0,
      request_payload: { model: "gpt-4" }, model_identifier: "gpt-4"
    )
    assert_equal 0, interaction.input_tokens
    assert_equal 0, interaction.output_tokens
  end

  test "stores JSONB request_payload correctly" do
    payload = { model: "gpt-4", temperature: 0.7, messages: [ { role: "user", content: "Hello" } ] }
    interaction = ModelInteraction.create!(
      account: @account, message: @message, sequence: 0,
      request_payload: payload, model_identifier: "gpt-4"
    )
    interaction.reload
    assert_equal "gpt-4", interaction.request_payload["model"]
    assert_equal 0.7, interaction.request_payload["temperature"]
  end

  test "stores JSONB response_payload correctly" do
    payload = { content: "Hi there", input_tokens: 10, output_tokens: 5 }
    interaction = ModelInteraction.create!(
      account: @account, message: @message, sequence: 0,
      request_payload: { model: "gpt-4" },
      response_payload: payload,
      model_identifier: "gpt-4"
    )
    interaction.reload
    assert_equal "Hi there", interaction.response_payload["content"]
    assert_equal 10, interaction.response_payload["input_tokens"]
  end
end
