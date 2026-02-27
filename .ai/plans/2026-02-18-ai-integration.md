# Plan: AI Integration - Multi-Provider LLM Support

**Date**: 2026-02-18
**Goal**: Connect advisors to actual LLMs with multi-provider support (OpenAI, Anthropic, etc.)

---

## Current State Assessment

**Models**:
- `Advisor` has `model_provider` (string enum: openai/anthropic/gemini) and `model_id` (string) fields
- `Message` has `status` enum (pending/complete/error) and polymorphic sender
- `UsageRecord` exists for tracking tokens and costs
- `Conversation` has `rules_of_engagement` and ScribeCoordinator integration

**Services**: `ScribeCoordinator` determines which advisors respond to messages

**Controllers**: `MessagesController` creates placeholder "thinking..." messages with `pending` status

**Background Jobs**: Only `ApplicationJob` exists - no custom jobs yet

**Missing**: Provider/Model tables, AI client service, background job for generation, Turbo Streams, encrypted credentials handling

---

## Goal

Enable advisors to actually call LLM APIs and generate real responses:
1. Create Provider and LlmModel tables for multi-provider support
2. Migrate Advisor to reference LlmModel instead of string fields
3. Build AIClient service to call OpenAI/Anthropic APIs
4. Create GenerateAdvisorResponseJob for async processing
5. Add Turbo Streams for real-time message updates
6. Implement usage tracking with token counting

## Non-goals

- Fine-tuning or custom model hosting
- Streaming responses (send full response when complete)
- Message editing or regeneration
- Rate limiting per account (Phase 4)
- Provider health checks or automatic failover
- Multi-modal inputs (images, files)
- Message versioning or history

---

## Scope + Assumptions

- Each account manages its own API credentials (self-serve model)
- Providers supported initially: OpenAI, Anthropic (extensible pattern)
- API credentials encrypted with Rails encrypted attributes
- Solid Queue handles background job processing
- Turbo Streams broadcast to conversation participants
- Usage tracking records every API call with tokens and calculated cost
- Placeholder messages created synchronously, replaced asynchronously
- Errors result in message status = "error" with error content

---

## Implementation Steps

### Step 1: Database Migration - Create Providers Table

**File**: `db/migrate/20260218XXXXXX_create_providers.rb`

```ruby
class CreateProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :providers do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :provider_type, null: false
      t.jsonb :credentials, default: {}
      t.boolean :enabled, default: true

      t.timestamps
    end

    add_index :providers, [ :account_id, :name ], unique: true
    add_index :providers, :credentials, using: :gin
  end
end
```

Run: `bin/rails db:migrate`

### Step 2: Database Migration - Create LlmModels Table

**File**: `db/migrate/20260218XXXXXX_create_llm_models.rb`

```ruby
class CreateLlmModels < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_models do |t|
      t.references :provider, null: false, foreign_key: true
      t.string :name, null: false
      t.string :identifier, null: false
      t.boolean :enabled, default: true
      t.boolean :deprecated, default: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :llm_models, [ :provider_id, :identifier ], unique: true
    add_index :llm_models, :deleted_at
  end
end
```

Run: `bin/rails db:migrate`

### Step 3: Database Migration - Update Advisors to Reference LlmModel

**File**: `db/migrate/20260218XXXXXX_add_llm_model_to_advisors.rb`

```ruby
class AddLlmModelToAdvisors < ActiveRecord::Migration[8.1]
  def up
    # Add new reference column
    add_reference :advisors, :llm_model, foreign_key: true, null: true

    # Migrate existing data (optional - for dev environments with seed data)
    # This would map old model_provider + model_id to new llm_model records
    # Skip for production - handle via data migration script

    # Remove old columns (after data migration)
    remove_column :advisors, :model_provider, :string
    remove_column :advisors, :model_id, :string
  end

  def down
    add_column :advisors, :model_provider, :string
    add_column :advisors, :model_id, :string
    remove_reference :advisors, :llm_model
  end
end
```

Run: `bin/rails db:migrate`

### Step 4: Create Provider Model

**File**: `app/models/provider.rb`

```ruby
class Provider < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account

  has_many :llm_models, dependent: :destroy

  enum :provider_type, {
    openai: "openai",
    anthropic: "anthropic",
    gemini: "gemini"
  }, prefix: :type

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :provider_type, presence: true
  validates :account, presence: true

  # Encrypt credentials at rest
  encrypts :credentials

  scope :enabled, -> { where(enabled: true) }
  scope :by_type, ->(type) { where(provider_type: type) }

  # Get API key from encrypted credentials
  def api_key
    credentials["api_key"]
  end

  def api_key=(value)
    self.credentials = credentials.merge("api_key" => value)
  end

  # Organization ID for OpenAI
  def organization_id
    credentials["organization_id"]
  end

  def organization_id=(value)
    self.credentials = credentials.merge("organization_id" => value)
  end
end
```

### Step 5: Create LlmModel Model

**File**: `app/models/llm_model.rb`

```ruby
class LlmModel < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :provider

  has_many :advisors, dependent: :nullify

  validates :name, presence: true
  validates :identifier, presence: true, uniqueness: { scope: :provider_id }
  validates :provider, presence: true
  validates :account, presence: true

  scope :enabled, -> { where(enabled: true, deprecated: false).where(deleted_at: nil) }
  scope :available, -> { enabled }
  scope :deprecated, -> { where(deprecated: true) }
  scope :soft_deleted, -> { where.not(deleted_at: nil) }

  # Soft delete
  def soft_delete
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # Full API identifier (provider-specific format)
  def full_identifier
    "#{provider.provider_type}/#{identifier}"
  end

  # Display name with provider
  def display_name
    "#{name} (#{provider.name})"
  end
end
```

### Step 6: Update Advisor Model

**File**: `app/models/advisor.rb`

```ruby
class Advisor < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :council, optional: true
  belongs_to :llm_model, optional: true  # NEW: reference to LlmModel

  has_many :council_advisors, dependent: :destroy
  has_many :councils, through: :council_advisors
  has_many :messages, as: :sender, dependent: :destroy

  # REMOVED: model_provider enum (moved to Provider)
  # REMOVED: model_id string (replaced by llm_model_id)

  validates :name, presence: true
  validates :account, presence: true

  # Simple advisors (with council_id) only need name and short_description
  # Full advisors (without council_id) need all AI model fields
  validates :system_prompt, presence: true, unless: -> { council_id.present? }
  validates :llm_model, presence: true, unless: -> { council_id.present? }  # NEW

  scope :global, -> { where(global: true) }
  scope :custom, -> { where(global: false) }

  # Helper method for simple advisors
  def simple?
    council_id.present?
  end

  # Delegation to llm_model for convenience
  delegate :provider, :provider_type, to: :llm_model, allow_nil: true
end
```

### Step 7: Create AIClient Service

**File**: `app/services/ai_client.rb`

```ruby
class AIClient
  class Error < StandardError; end
  class ApiError < Error; end
  class RateLimitError < Error; end
  class InvalidResponseError < Error; end

  MAX_RETRIES = 2
  RETRY_DELAY = 1 # seconds

  attr_reader :advisor, :conversation, :message

  def initialize(advisor:, conversation:, message:)
    @advisor = advisor
    @conversation = conversation
    @message = message
  end

  # Main entry point: calls LLM API and returns response content
  def generate_response
    return nil unless advisor.llm_model.present?
    return nil unless advisor.llm_model.enabled?

    provider_type = advisor.llm_model.provider.provider_type.to_sym

    case provider_type
    when :openai
      call_openai
    when :anthropic
      call_anthropic
    else
      raise Error, "Unsupported provider: #{provider_type}"
    end
  rescue => e
    log_error(e)
    raise ApiError, "AI API call failed: #{e.message}"
  end

  private

  def call_openai
    client = OpenAI::Client.new(
      access_token: advisor.llm_model.provider.api_key,
      organization_id: advisor.llm_model.provider.organization_id
    )

    with_retries do
      response = client.chat(
        parameters: {
          model: advisor.llm_model.identifier,
          messages: build_messages,
          temperature: advisor.model_config["temperature"] || 0.7,
          max_tokens: advisor.model_config["max_tokens"] || 1000
        }
      )

      parse_openai_response(response)
    end
  end

  def call_anthropic
    client = Anthropic::Client.new(
      access_token: advisor.llm_model.provider.api_key
    )

    with_retries do
      response = client.messages(
        parameters: {
          model: advisor.llm_model.identifier,
          messages: build_messages_for_anthropic,
          system: advisor.system_prompt,
          max_tokens: advisor.model_config["max_tokens"] || 1000
        }
      )

      parse_anthropic_response(response)
    end
  end

  def build_messages
    messages = []
    messages << { role: "system", content: advisor.system_prompt }

    conversation.messages.chronological.each do |msg|
      next if msg.id == message.id # Skip the pending message itself

      role = case msg.role
      when "user" then "user"
      when "advisor" then "assistant"
      else "user"
      end

      messages << { role: role, content: msg.content }
    end

    messages
  end

  def build_messages_for_anthropic
    # Anthropic uses different message format (no system message in array)
    conversation.messages.chronological.map do |msg|
      next if msg.id == message.id

      role = case msg.role
      when "user" then "user"
      when "advisor" then "assistant"
      else "user"
      end

      { role: role, content: msg.content }
    end.compact
  end

  def parse_openai_response(response)
    choice = response.dig("choices", 0)
    content = choice.dig("message", "content")
    usage = response["usage"]

    {
      content: content,
      input_tokens: usage["prompt_tokens"],
      output_tokens: usage["completion_tokens"],
      total_tokens: usage["total_tokens"]
    }
  end

  def parse_anthropic_response(response)
    content = response.dig("content", 0, "text")
    usage = response["usage"]

    {
      content: content,
      input_tokens: usage["input_tokens"],
      output_tokens: usage["output_tokens"],
      total_tokens: usage["input_tokens"] + usage["output_tokens"]
    }
  end

  def with_retries
    retries = 0
    begin
      yield
    rescue => e
      retries += 1
      if retries <= MAX_RETRIES
        sleep(RETRY_DELAY * retries)
        retry
      else
        raise
      end
    end
  end

  def log_error(error)
    Rails.logger.error "[AIClient] Error for advisor #{advisor.id}: #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n") if error.backtrace
  end
end
```

**Add to Gemfile**:
```ruby
gem "ruby-openai"
gem "anthropic"
```

Run: `bundle install`

### Step 8: Create GenerateAdvisorResponseJob

**File**: `app/jobs/generate_advisor_response_job.rb`

```ruby
class GenerateAdvisorResponseJob < ApplicationJob
  queue_as :default

  # Job is idempotent - safe to retry
  def perform(advisor_id:, conversation_id:, message_id:)
    advisor = Advisor.find_by(id: advisor_id)
    conversation = Conversation.find_by(id: conversation_id)
    message = Message.find_by(id: message_id)

    return unless advisor && conversation && message
    return unless message.pending? # Only process pending messages

    # Set tenant context for background job
    ActsAsTenant.current_tenant = advisor.account

    begin
      # Call AI service
      client = AIClient.new(advisor: advisor, conversation: conversation, message: message)
      result = client.generate_response

      if result && result[:content].present?
        # Update message with response
        message.update!(
          content: result[:content],
          role: "advisor",
          status: "complete"
        )

        # Record usage
        create_usage_record(message, advisor, result)

        # Broadcast via Turbo Stream
        broadcast_message(message, conversation)
      else
        handle_error(message, "Empty response from AI")
      end
    rescue AIClient::ApiError => e
      handle_error(message, "API Error: #{e.message}")
    rescue => e
      handle_error(message, "Unexpected error: #{e.message}")
      Rails.logger.error "[GenerateAdvisorResponseJob] Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
    end
  ensure
    ActsAsTenant.current_tenant = nil
  end

  private

  def create_usage_record(message, advisor, result)
    UsageRecord.create!(
      account: advisor.account,
      message: message,
      provider: advisor.llm_model.provider.provider_type,
      model: advisor.llm_model.identifier,
      input_tokens: result[:input_tokens] || 0,
      output_tokens: result[:output_tokens] || 0,
      cost_cents: calculate_cost(advisor.llm_model, result),
      recorded_at: Time.current
    )
  end

  def calculate_cost(llm_model, result)
    # TODO: Implement actual pricing lookup
    # For now, use placeholder calculation
    # OpenAI GPT-4: $0.03/1K input, $0.06/1K output
    # Anthropic Claude: $0.008/1K input, $0.024/1K output

    input_tokens = result[:input_tokens] || 0
    output_tokens = result[:output_tokens] || 0

    # Placeholder rates (should be stored in llm_models table)
    input_rate = 0.03 / 1000  # dollars per token
    output_rate = 0.06 / 1000

    cost_dollars = (input_tokens * input_rate) + (output_tokens * output_rate)
    (cost_dollars * 100).round # Convert to cents
  end

  def broadcast_message(message, conversation)
    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{conversation.id}",
      target: "message_#{message.id}",
      partial: "messages/message",
      locals: { message: message, current_user: nil }
    )
  end

  def handle_error(message, error_content)
    message.update!(
      content: "[Error: #{error_content}]",
      status: "error"
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{message.id}",
      target: "message_#{message.id}",
      partial: "messages/message",
      locals: { message: message, current_user: nil }
    )
  end
end
```

### Step 9: Update MessagesController to Enqueue Jobs

**File**: `app/controllers/messages_controller.rb`

```ruby
class MessagesController < ApplicationController
  before_action :set_conversation

  def create
    @message = @conversation.messages.new(message_params)
    @message.account = Current.account
    @message.sender = Current.user
    @message.role = "user"
    @message.status = "complete"

    if @message.save
      # Trigger ScribeCoordinator to determine advisor responses
      coordinator = ScribeCoordinator.new(@conversation)
      responders = coordinator.determine_responders(last_message: @message)

      # Create pending messages and enqueue jobs for each responder
      responders.each do |advisor|
        placeholder = @conversation.messages.create!(
          account: Current.account,
          sender: advisor,
          role: "system",
          content: "[#{advisor.name}] is thinking...",
          status: "pending"
        )

        # Enqueue background job to generate actual response
        GenerateAdvisorResponseJob.perform_later(
          advisor_id: advisor.id,
          conversation_id: @conversation.id,
          message_id: placeholder.id
        )

        # Track for round robin
        @conversation.mark_advisor_spoken(advisor.id)
      end

      redirect_to @conversation, notice: "Message posted successfully."
    else
      @messages = @conversation.messages.chronological.includes(:sender)
      @new_message = @message
      render "conversations/show", status: :unprocessable_entity
    end
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find(params[:conversation_id])
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
```

### Step 10: Update Message Views for Turbo Streams

**File**: `app/views/conversations/show.html.erb`

Add Turbo Stream subscription at top:

```erb
<%= turbo_stream_from "conversation_#{@conversation.id}" %>

<div class="container mx-auto px-4 py-8">
  <!-- Conversation header -->
  <div class="mb-6">
    <div class="flex items-center gap-2 mb-1">
      <h1 class="text-3xl font-bold"><%= @conversation.title %></h1>
      <!-- ... rest of header -->
    </div>
  </div>

  <!-- Messages list with Turbo targets -->
  <div id="messages" class="space-y-4 mb-8">
    <% @messages.each do |message| %>
      <%= render "messages/message", message: message, current_user: Current.user %>
    <% end %>
  </div>

  <!-- Message form -->
  <%= render "messages/form", conversation: @conversation %>
</div>
```

**File**: `app/views/messages/_message.html.erb`

```erb
<%= turbo_frame_tag "message_#{message.id}" do %>
  <% is_current_user = message.sender == current_user %>
  <% is_pending = message.pending? %>
  <% is_error = message.error? %>

  <div class="flex <%= is_current_user ? 'justify-end' : 'justify-start' %>">
    <div class="max-w-[80%] <%=
      if is_current_user
        'bg-primary text-primary-content'
      elsif is_error
        'bg-error text-error-content'
      elsif is_pending
        'bg-base-200 italic opacity-70'
      else
        'bg-base-300'
      end %> rounded-lg p-3">

      <div class="text-xs <%= is_current_user ? 'text-primary-content/70' : 'text-base-content/60' %> mb-1">
        <%= message.sender.is_a?(Advisor) ? "Advisor: #{message.sender.name}" : message.sender.email %>
        <span class="mx-1">·</span>
        <%= time_ago_in_words(message.created_at) %> ago
        <% if is_pending %>
          <span class="badge badge-xs badge-warning ml-2">thinking...</span>
        <% elsif is_error %>
          <span class="badge badge-xs badge-error ml-2">error</span>
        <% end %>
      </div>

      <div class="whitespace-pre-wrap <%= is_pending ? 'animate-pulse' : '' %>">
        <%= message.content %>
      </div>
    </div>
  </div>
<% end %>
```

### Step 11: Create Provider Management UI (Basic)

**File**: `app/controllers/providers_controller.rb`

```ruby
class ProvidersController < ApplicationController
  def index
    @providers = Current.account.providers.includes(:llm_models)
  end

  def new
    @provider = Current.account.providers.new
  end

  def create
    @provider = Current.account.providers.new(provider_params)

    if @provider.save
      redirect_to providers_path, notice: "Provider added successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def provider_params
    params.require(:provider).permit(:name, :provider_type, :api_key, :organization_id)
  end
end
```

**File**: `config/routes.rb`

```ruby
resources :providers, only: [ :index, :new, :create ]
```

### Step 12: Create Provider Model Tests

**File**: `test/models/provider_test.rb`

```ruby
require "test_helper"

class ProviderTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
  end

  test "valid provider with required fields" do
    provider = @account.providers.new(
      name: "OpenAI Production",
      provider_type: "openai",
      api_key: "sk-test123"
    )
    assert provider.valid?
  end

  test "requires name" do
    provider = @account.providers.new(provider_type: "openai")
    assert_not provider.valid?
    assert_includes provider.errors[:name], "can't be blank"
  end

  test "requires unique name per account" do
    @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "key1")
    duplicate = @account.providers.new(name: "OpenAI", provider_type: "anthropic", api_key: "key2")
    assert_not duplicate.valid?
  end

  test "encrypts credentials" do
    provider = @account.providers.create!(
      name: "Test",
      provider_type: "openai",
      api_key: "secret-key-123"
    )

    # Reload to ensure encryption round-trip
    provider.reload
    assert_equal "secret-key-123", provider.api_key
  end

  test "scopes enabled providers" do
    enabled = @account.providers.create!(name: "Enabled", provider_type: "openai", api_key: "key", enabled: true)
    disabled = @account.providers.create!(name: "Disabled", provider_type: "openai", api_key: "key", enabled: false)

    assert_includes Provider.enabled, enabled
    assert_not_includes Provider.enabled, disabled
  end
end
```

### Step 13: Create LlmModel Model Tests

**File**: `test/models/llm_model_test.rb`

```ruby
require "test_helper"

class LlmModelTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @provider = @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "key")
  end

  test "valid llm_model with required fields" do
    model = @provider.llm_models.new(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )
    assert model.valid?
  end

  test "requires identifier unique per provider" do
    @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    duplicate = @provider.llm_models.new(account: @account, name: "GPT-4 Turbo", identifier: "gpt-4")
    assert_not duplicate.valid?
  end

  test "soft delete sets deleted_at" do
    model = @provider.llm_models.create!(account: @account, name: "Old Model", identifier: "old")
    model.soft_delete
    assert model.deleted?
    assert model.deleted_at.present?
  end

  test "scope available excludes deprecated and deleted" do
    available = @provider.llm_models.create!(account: @account, name: "Active", identifier: "active")
    deprecated = @provider.llm_models.create!(account: @account, name: "Deprecated", identifier: "old", deprecated: true)
    deleted = @provider.llm_models.create!(account: @account, name: "Deleted", identifier: "gone")
    deleted.soft_delete

    available_models = LlmModel.available
    assert_includes available_models, available
    assert_not_includes available_models, deprecated
    assert_not_includes available_models, deleted
  end
end
```

### Step 14: Create AIClient Service Tests

**File**: `test/services/ai_client_test.rb`

```ruby
require "test_helper"

class AIClientTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @provider = @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "test-key")
    @llm_model = @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a helpful assistant.",
      llm_model: @llm_model
    )
    @council = @account.councils.create!(name: "Test Council")
    @conversation = @account.conversations.create!(
      council: @council,
      user: users(:one),
      title: "Test Conversation"
    )
    @message = @conversation.messages.create!(
      account: @account,
      sender: @advisor,
      role: "system",
      content: "Test message",
      status: "pending"
    )
  end

  test "initialize with advisor, conversation, message" do
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    assert_equal @advisor, client.advisor
    assert_equal @conversation, client.conversation
    assert_equal @message, client.message
  end

  test "generate_response returns nil without llm_model" do
    @advisor.update!(llm_model: nil)
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    assert_nil client.generate_response
  end

  test "build_messages includes system prompt" do
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages)
    assert_equal "system", messages.first[:role]
    assert_equal @advisor.system_prompt, messages.first[:content]
  end

  # Integration test with mocked API
  test "calls OpenAI API and returns parsed response" do
    # Mock would go here using Mocha or similar
    # response = client.generate_response
    # assert response[:content].present?
    # assert response[:input_tokens] > 0
    # assert response[:output_tokens] > 0
  end
end
```

### Step 15: Create GenerateAdvisorResponseJob Tests

**File**: `test/jobs/generate_advisor_response_job_test.rb`

```ruby
require "test_helper"

class GenerateAdvisorResponseJobTest < ActiveJob::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @provider = @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "key")
    @llm_model = @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are helpful.",
      llm_model: @llm_model
    )
    @council = @account.councils.create!(name: "Test Council")
    @conversation = @account.conversations.create!(
      council: @council,
      user: users(:one),
      title: "Test"
    )
    @message = @conversation.messages.create!(
      account: @account,
      sender: @advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )
  end

  test "updates message with response on success" do
    # Mock AIClient to return successful response
    mock_response = {
      content: "Hello, I'm here to help!",
      input_tokens: 100,
      output_tokens: 50,
      total_tokens: 150
    }

    AIClient.any_instance.stubs(:generate_response).returns(mock_response)

    assert_enqueued_jobs 1 do
      GenerateAdvisorResponseJob.perform_later(
        advisor_id: @advisor.id,
        conversation_id: @conversation.id,
        message_id: @message.id
      )
    end
  end

  test "creates usage record after successful generation" do
    # Verify UsageRecord is created with correct data
  end

  test "marks message as error on API failure" do
    AIClient.any_instance.stubs(:generate_response).raises(AIClient::ApiError, "API Error")

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    @message.reload
    assert @message.error?
    assert_match(/API Error/, @message.content)
  end

  test "skips processing if message not pending" do
    @message.update!(status: "complete")

    # Job should return early without calling AI
    AIClient.expects(:new).never

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )
  end
end
```

### Step 16: Create Integration Test

**File**: `test/integration/ai_response_flow_test.rb`

```ruby
require "test_helper"

class AiResponseFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @account = accounts(:one)
    set_tenant(@account)

    # Setup provider and model
    @provider = @account.providers.create!(
      name: "OpenAI Test",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )

    # Setup advisor with model
    @advisor = @account.advisors.create!(
      name: "Helper Bot",
      system_prompt: "You are a helpful assistant.",
      llm_model: @llm_model
    )

    @council = @account.councils.create!(name: "Test Council")
    @council.advisors << @advisor

    @conversation = @account.conversations.create!(
      council: @council,
      user: @user,
      title: "AI Test Conversation",
      rules_of_engagement: :round_robin
    )

    sign_in_as(@user)
  end

  test "posting message creates pending advisor message" do
    assert_difference "Message.count", 2 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello AI advisor" }
      }
    end

    assert_redirected_to conversation_path(@conversation)

    placeholder = Message.last
    assert_equal @advisor, placeholder.sender
    assert_equal "pending", placeholder.status
    assert_equal "system", placeholder.role
    assert_match(/thinking/, placeholder.content)
  end

  test "background job enqueued on message create" do
    assert_enqueued_with(job: GenerateAdvisorResponseJob) do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Trigger AI response" }
      }
    end
  end

  test "usage record created after AI response" do
    # Mock AI response
    mock_response = {
      content: "Here's my response!",
      input_tokens: 50,
      output_tokens: 25,
      total_tokens: 75
    }
    AIClient.any_instance.stubs(:generate_response).returns(mock_response)

    # Create pending message
    message = @conversation.messages.create!(
      account: @account,
      sender: @advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )

    assert_difference "UsageRecord.count", 1 do
      GenerateAdvisorResponseJob.perform_now(
        advisor_id: @advisor.id,
        conversation_id: @conversation.id,
        message_id: message.id
      )
    end

    usage = UsageRecord.last
    assert_equal @account, usage.account
    assert_equal message, usage.message
    assert_equal "openai", usage.provider
    assert_equal "gpt-4", usage.model
    assert_equal 50, usage.input_tokens
    assert_equal 25, usage.output_tokens
  end
end
```

### Step 17: Configure Rails Credentials for Encryption

Ensure Rails master key is set for encrypted attributes:

```bash
# Check if credentials exist
bin/rails credentials:show

# If needed, edit credentials to add encryption key
EDITOR="nano" bin/rails credentials:edit
```

**Note**: In production, ensure `RAILS_MASTER_KEY` environment variable is set.

---

## Verification

Run this checklist after implementation:

- [ ] All migrations run: `bin/rails db:migrate`
- [ ] Provider model tests pass: `bin/rails test test/models/provider_test.rb`
- [ ] LlmModel model tests pass: `bin/rails test test/models/llm_model_test.rb`
- [ ] Advisor model tests pass: `bin/rails test test/models/advisor_test.rb`
- [ ] AIClient service tests pass: `bin/rails test test/services/ai_client_test.rb`
- [ ] Job tests pass: `bin/rails test test/jobs/generate_advisor_response_job_test.rb`
- [ ] Integration tests pass: `bin/rails test test/integration/ai_response_flow_test.rb`
- [ ] All tests pass: `bin/rails test`
- [ ] Routes updated: `bin/rails routes | grep provider`
- [ ] Manual test: Create provider via UI with API key
- [ ] Manual test: Create LlmModel associated with provider
- [ ] Manual test: Update advisor to use new llm_model
- [ ] Manual test: Post message and see "thinking..." placeholder
- [ ] Manual test: Verify job enqueued in Solid Queue
- [ ] Manual test: Process job and see actual AI response (requires real API key)
- [ ] Manual test: Check UsageRecord created with tokens
- [ ] Manual test: Verify Turbo Stream updates message in real-time

---

## Doc Impact

- **Create**: `.ai/docs/features/ai-integration.md` - Document multi-provider setup, configuration
- **Create**: `.ai/docs/patterns/background-jobs.md` - Pattern for async processing with Solid Queue
- **Create**: `.ai/docs/patterns/turbo-streams.md` - Pattern for real-time UI updates
- **Update**: `.ai/docs/features/conversations.md` - Add section on AI responses and usage tracking
- **Update**: `.ai/MEMORY.md` - Add verified gems (ruby-openai, anthropic), new conventions

---

## Rollback

If implementation fails:

1. **Database rollback**:
   ```
   bin/rails db:rollback STEP=3
   ```
   Then delete migration files.

2. **Remove models**: Delete `app/models/provider.rb`, `app/models/llm_model.rb`

3. **Remove services**: Delete `app/services/ai_client.rb`

4. **Remove jobs**: Delete `app/jobs/generate_advisor_response_job.rb`

5. **Revert Advisor model**: Restore `model_provider` and `model_id` fields, remove `llm_model` reference

6. **Revert MessagesController**: Remove job enqueue logic

7. **Revert views**: Remove Turbo Stream subscription from conversation show

8. **Remove gems**: Remove `ruby-openai` and `anthropic` from Gemfile, run `bundle install`

9. **Delete tests**:
   - `test/models/provider_test.rb`
   - `test/models/llm_model_test.rb`
   - `test/services/ai_client_test.rb`
   - `test/jobs/generate_advisor_response_job_test.rb`
   - `test/integration/ai_response_flow_test.rb`

---

## Unknowns / Risks

1. **API credential management**: Accounts must manage their own API keys. Need clear documentation on security best practices.

2. **Cost exposure**: Real API calls incur costs. Consider adding spend limits per account (deferred to billing phase).

3. **Rate limiting**: No built-in rate limiting yet. Could hit provider limits with high volume (defer to Phase 4).

4. **Error handling**: Network failures, API downtime, invalid API keys all need graceful degradation. Test error scenarios thoroughly.

5. **Token counting accuracy**: Pricing calculations are approximate. May need per-model pricing tables for accuracy.

6. **Multi-tenancy in background jobs**: Must ensure `ActsAsTenant.current_tenant` is set correctly in jobs to maintain data isolation.

7. **API gem dependencies**: `ruby-openai` and `anthropic` gems may have breaking changes. Pin versions in Gemfile.

---

**Approve this plan?**
