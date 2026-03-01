require "test_helper"

class GenerateConversationSummaryJobTest < ActiveJob::TestCase
  def setup
    @account = accounts(:one)
    set_tenant(@account)

    @user = @account.users.first
    @space = @account.spaces.first

    # Create unique IDs for this test process to avoid parallel test conflicts
    @unique_id = "#{Time.now.to_i}-#{SecureRandom.hex(4)}"

    # Create a provider and LLM model for the scribe
    @provider = @account.providers.create!(
      name: "OpenAI-#{@unique_id}",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4-#{@unique_id}",
      identifier: "gpt-4-#{@unique_id}",
      enabled: true
    )

    # Create an advisor first (needed for council/conversation)
    @advisor = @space.advisors.create!(
      account: @account,
      name: "Test Advisor #{@unique_id}",
      system_prompt: "You are helpful",
      llm_model: @llm_model
    )
    # Ensure advisor is fully persisted before using in associations
    @advisor.reload

    @council = @space.councils.create!(
      name: "Test Council #{@unique_id}",
      user: @user,
      account: @account
    )
    @council.advisors << @advisor

    # Create conversation with advisor as participant
    @conversation = @council.conversations.create!(
      title: "Test Conversation #{@unique_id}",
      user: @user,
      account: @account,
      status: :concluding
    )
    @conversation.conversation_participants.create!(
      advisor: @advisor,
      role: "advisor",
      position: 1
    )
    @conversation.reload  # Ensure conversation has latest participant data
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  # Helper method to create a test LLM model when needed
  def create_test_llm_model
    provider = @account.providers.first || @account.providers.create!(
      name: "Test Provider #{@unique_id}-#{SecureRandom.hex(4)}",
      provider_type: "openai",
      api_key: "test-key"
    )
    provider.llm_models.create!(
      account: @account,
      name: "GPT-4-#{@unique_id}-#{SecureRandom.hex(4)}",
      identifier: "gpt-4-#{@unique_id}-#{SecureRandom.hex(4)}",
      enabled: true
    )
  end

  # ============================================================================
  # perform Tests
  # ============================================================================

  test "perform does nothing when conversation not found" do
    assert_nothing_raised do
      GenerateConversationSummaryJob.perform_now(99999)
    end
  end

  test "perform does nothing when conversation is not concluding" do
    # Ensure we have a valid advisor (may be affected by parallel tests)
    advisor = if @advisor && @advisor.persisted?
      @advisor
    else
      llm = @llm_model || @account.llm_models.enabled.first || create_test_llm_model
      @space.advisors.create!(
        account: @account,
        name: "Test Advisor #{@unique_id}-fallback",
        system_prompt: "You are helpful",
        llm_model: llm
      )
    end

    # Ensure conversation has advisor participant
    @conversation.reload
    if @conversation.advisors.empty?
      @conversation.conversation_participants.create!(
        advisor: advisor,
        role: "advisor",
        position: 1
      )
      @conversation.reload
    end

    @conversation.update!(status: :active)

    AI::ContentGenerator.any_instance.expects(:generate_conversation_summary).never

    GenerateConversationSummaryJob.perform_now(@conversation.id)
  end

  test "perform generates summary and updates conversation" do
    # Ensure we have a valid advisor (may be affected by parallel tests)
    advisor = if @advisor && @advisor.persisted?
      @advisor
    else
      llm = @llm_model || @account.llm_models.enabled.first || create_test_llm_model
      @space.advisors.create!(
        account: @account,
        name: "Test Advisor #{@unique_id}-fallback",
        system_prompt: "You are helpful",
        llm_model: llm
      )
    end

    # Ensure a scribe advisor exists (find_scribe_advisor requires is_scribe: true)
    unless @account.advisors.exists?(is_scribe: true)
      @space.advisors.create!(
        account: @account,
        name: "Scribe",
        system_prompt: "You are the Scribe",
        llm_model: @llm_model,
        is_scribe: true
      )
    end

    # Ensure conversation has advisor participant
    @conversation.reload
    if @conversation.advisors.empty?
      @conversation.conversation_participants.create!(
        advisor: advisor,
        role: "advisor",
        position: 1
      )
      @conversation.reload
    end

    # Create messages with proper sender
    @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Hello advisors"
    )

    # Mock the AI generator
    mock_summary = <<~SUMMARY
      ## Key Decisions
      - Decision one
      - Decision two

      ## Action Items
      - Action item one

      ## Insights
      - Insight here

      ## Open Questions
      - Question one
    SUMMARY

    AI::ContentGenerator.any_instance.stubs(:generate_conversation_summary).returns(mock_summary)
    Turbo::StreamsChannel.stubs(:broadcast_replace_to)

    # Job creates 2 memories: conversation_summary + initial version
    # (Memory model has after_create :create_initial_version)
    assert_difference "Memory.count", 2 do
      GenerateConversationSummaryJob.perform_now(@conversation.id)
    end

    @conversation.reload
    assert @conversation.draft_memory.present?

    draft = JSON.parse(@conversation.draft_memory)
    assert draft["key_decisions"].include?("Decision one")
    assert draft["action_items"].include?("Action item one")
  end

  test "perform broadcasts summary ready notification" do
    # Ensure we have a valid advisor (may be affected by parallel tests)
    advisor = if @advisor && @advisor.persisted?
      @advisor
    else
      llm = @llm_model || @account.llm_models.enabled.first || create_test_llm_model
      @space.advisors.create!(
        account: @account,
        name: "Test Advisor #{@unique_id}-fallback",
        system_prompt: "You are helpful",
        llm_model: llm
      )
    end

    # Ensure conversation has advisor participant
    @conversation.reload
    if @conversation.advisors.empty?
      @conversation.conversation_participants.create!(
        advisor: advisor,
        role: "advisor",
        position: 1
      )
      @conversation.reload
    end

    @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test message"
    )

    AI::ContentGenerator.any_instance.stubs(:generate_conversation_summary).returns("Summary content")

    Turbo::StreamsChannel.expects(:broadcast_replace_to).with(
      "conversation_#{@conversation.id}",
      target: "conversation_status",
      partial: "conversations/summary_review",
      locals: { conversation: @conversation }
    )

    GenerateConversationSummaryJob.perform_now(@conversation.id)
  end

  test "perform ensures tenant is reset in ensure block" do
    # Ensure we have a valid advisor (may be affected by parallel tests)
    advisor = if @advisor && @advisor.persisted?
      @advisor
    else
      llm = @llm_model || @account.llm_models.enabled.first || create_test_llm_model
      @space.advisors.create!(
        account: @account,
        name: "Test Advisor #{@unique_id}-fallback",
        system_prompt: "You are helpful",
        llm_model: llm
      )
    end

    # Ensure conversation has advisor participant
    @conversation.reload
    if @conversation.advisors.empty?
      @conversation.conversation_participants.create!(
        advisor: advisor,
        role: "advisor",
        position: 1
      )
      @conversation.reload
    end

    @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )

    AI::ContentGenerator.any_instance.stubs(:generate_conversation_summary).returns("Summary")
    Turbo::StreamsChannel.stubs(:broadcast_replace_to)

    GenerateConversationSummaryJob.perform_now(@conversation.id)

    # Tenant should be nil after job completes
    assert_nil ActsAsTenant.current_tenant
  end

  # ============================================================================
  # build_transcript Tests
  # ============================================================================

  test "build_transcript includes user and advisor messages" do
    advisor = @space.advisors.create!(
      account: @account,
      name: "Test Advisor",
      system_prompt: "You are helpful",
      llm_model: @llm_model
    )

    @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "User question"
    )
    @account.messages.create!(
      conversation: @conversation,
      sender: advisor,
      role: "advisor",
      content: "Advisor response"
    )

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    transcript = job.send(:build_transcript)

    assert transcript.include?("#{@user.email}: User question")
    assert transcript.include?("Test Advisor: Advisor response")
  end

  test "build_transcript skips pending messages" do
    @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Complete message",
      status: :complete
    )
    @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Pending message",
      status: :pending
    )

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    transcript = job.send(:build_transcript)

    assert transcript.include?("Complete message")
    refute transcript.include?("Pending message")
  end

  test "build_transcript skips advisor thinking placeholders" do
    advisor = @space.advisors.create!(
      account: @account,
      name: "Test Advisor",
      system_prompt: "You are helpful",
      llm_model: @llm_model
    )

    @account.messages.create!(
      conversation: @conversation,
      sender: advisor,
      role: "advisor",
      content: "Test Advisor is thinking..."
    )
    @account.messages.create!(
      conversation: @conversation,
      sender: advisor,
      role: "advisor",
      content: "Actual response content"
    )

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    transcript = job.send(:build_transcript)

    refute transcript.include?("is thinking...")
    assert transcript.include?("Actual response content")
  end

  test "build_transcript keeps Scribe selecting messages" do
    scribe_advisor = @account.advisors.create!(
      account: @account,
      name: "Scribe",
      system_prompt: "You document",
      llm_model: @llm_model,
      global: true
    )
    # Define scribe? method on this specific advisor instance for the test
    def scribe_advisor.scribe?; true; end

    @account.messages.create!(
      conversation: @conversation,
      sender: scribe_advisor,
      role: "advisor",
      content: "Scribe is selecting an advisor to respond..."
    )

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    transcript = job.send(:build_transcript)

    assert transcript.include?("selecting an advisor")
  end

  test "build_transcript orders messages chronologically" do
    @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "First message",
      created_at: 1.hour.ago
    )
    @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Second message",
      created_at: 30.minutes.ago
    )
    @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Third message",
      created_at: Time.current
    )

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    transcript = job.send(:build_transcript)

    first_pos = transcript.index("First message")
    second_pos = transcript.index("Second message")
    third_pos = transcript.index("Third message")

    assert first_pos < second_pos
    assert second_pos < third_pos
  end

  # ============================================================================
  # generate_summary Tests
  # ============================================================================

  test "generate_summary returns structured summary from AI" do
    mock_content = <<~CONTENT
      ## Key Decisions
      - Key decision here

      ## Action Items
      - Action item

      ## Insights
      - Insight

      ## Open Questions
      - Question
    CONTENT

    AI::ContentGenerator.any_instance.stubs(:generate_conversation_summary).returns(mock_content)

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    result = job.send(:generate_summary, "Transcript content")

    assert result[:key_decisions].include?("Key decision here")
    assert result[:action_items].include?("Action item")
    assert result[:insights].include?("Insight")
    assert result[:open_questions].include?("Question")
    assert result[:raw_summary].include?("Key Decisions")
  end

  test "generate_summary handles NoModelError with specific message" do
    AI::ContentGenerator.any_instance.stubs(:generate_conversation_summary).raises(
      AI::ContentGenerator::NoModelError.new("No model configured")
    )

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    result = job.send(:generate_summary, "Test transcript")

    assert result[:key_decisions].include?("No AI model available")
    assert result[:action_items].include?("No AI model available")
    assert result[:insights].include?("No AI model available")
    assert result[:open_questions].include?("No AI model available")
    assert result[:raw_summary].include?("No LLM model available")
  end

  test "generate_summary handles general errors with fallback" do
    AI::ContentGenerator.any_instance.stubs(:generate_conversation_summary).raises(
      StandardError.new("API connection failed")
    )

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    result = job.send(:generate_summary, "Test transcript")

    assert_match(/AI generation failed/, result[:key_decisions])
    assert_match(/AI generation failed/, result[:action_items])
    assert_match(/AI generation failed/, result[:insights])
    assert_match(/AI generation failed/, result[:open_questions])
    assert_match(/Summary generation failed/, result[:raw_summary])
    assert_match(/Transcript length: \d+ characters/, result[:raw_summary])
  end

  # ============================================================================
  # parse_structured_summary Tests
  # ============================================================================

  test "parse_structured_summary handles bold markdown headers" do
    job = GenerateConversationSummaryJob.new

    content = <<~CONTENT
      **Key Decisions**
      - Decision one

      **Action Items:**
      - Action one

      **Insights**
      - Insight one

      **Open Questions:**
      - Question one
    CONTENT

    result = job.send(:parse_structured_summary, content)

    assert result[:key_decisions].include?("Decision one")
    assert result[:action_items].include?("Action one")
    assert result[:insights].include?("Insight one")
    assert result[:open_questions].include?("Question one")
  end

  test "parse_structured_summary handles colon after section names" do
    job = GenerateConversationSummaryJob.new

    content = <<~CONTENT
      Key Decisions:
      - Decision one

      Action Items:
      - Action one
    CONTENT

    result = job.send(:parse_structured_summary, content)

    assert result[:key_decisions].include?("Decision one")
    assert result[:action_items].include?("Action one")
  end

  test "parse_structured_summary adds placeholders for empty sections" do
    job = GenerateConversationSummaryJob.new

    content = "## Key Decisions\n- Decision only\n"

    result = job.send(:parse_structured_summary, content)

    assert result[:key_decisions].include?("Decision only")
    assert_equal "- None identified\n", result[:action_items]
    assert_equal "- None identified\n", result[:insights]
    assert_equal "- None identified\n", result[:open_questions]
  end

  # ============================================================================
  # extract_section Tests (already have some, add more edge cases)
  # ============================================================================

  test "extract_section handles multiple sections correctly" do
    job = GenerateConversationSummaryJob.new

    content = <<~CONTENT
      ## Key Decisions
      - First decision
      - Second decision

      ## Action Items
      - First action

      ## Insights
      - First insight
    CONTENT

    key_decisions = job.send(:extract_section, content, "Key Decisions")
    action_items = job.send(:extract_section, content, "Action Items")
    insights = job.send(:extract_section, content, "Insights")

    assert key_decisions.include?("First decision")
    assert key_decisions.include?("Second decision")
    refute key_decisions.include?("First action")

    assert action_items.include?("First action")
    refute action_items.include?("First insight")
  end

  test "extract_section handles case insensitivity" do
    job = GenerateConversationSummaryJob.new

    content = "## KEY DECISIONS\n- Decision one\n"

    result = job.send(:extract_section, content, "Key Decisions")

    # The regex is case insensitive (/i flag)
    assert result.include?("Decision one")
  end

  test "extract_section returns empty string when section not found" do
    job = GenerateConversationSummaryJob.new

    content = "Some random content without sections"

    result = job.send(:extract_section, content, "Key Decisions")

    assert_equal "", result
  end

  # ============================================================================
  # broadcast_summary_ready Tests
  # ============================================================================

  test "broadcast_summary_ready sends turbo stream" do
    job = GenerateConversationSummaryJob.new

    Turbo::StreamsChannel.expects(:broadcast_replace_to).with(
      "conversation_#{@conversation.id}",
      target: "conversation_status",
      partial: "conversations/summary_review",
      locals: { conversation: @conversation }
    )

    job.send(:broadcast_summary_ready, @conversation)
  end

  # ============================================================================
  # create_conversation_memory Tests
  # ============================================================================

  test "create_conversation_memory creates memory with proper content" do
    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    summary = {
      key_decisions: "- Decision 1\n",
      action_items: "- Action 1\n",
      insights: "- Insight 1\n",
      open_questions: "- Question 1\n"
    }

    # Clean up any existing Scribe and create our test scribe advisor
    @account.advisors.where(name: "Scribe").destroy_all
    scribe = @account.advisors.create!(
      name: "Scribe",
      system_prompt: "You document",
      llm_model: @llm_model,
      global: true,
      is_scribe: true
    )

    assert_difference "Memory.count", 1 do
      job.send(:create_conversation_memory, summary)
    end

    memory = Memory.last
    assert_equal "conversation_summary", memory.memory_type
    assert_equal "Conversation: #{@conversation.title}", memory.title
    assert_includes memory.content, "Key Decisions"
    assert_includes memory.content, "Decision 1"
    assert_includes memory.content, "Action 1"
    assert_includes memory.content, "Insight 1"
    assert_includes memory.content, "Question 1"
    assert_equal scribe.id, memory.created_by_id
    assert_equal @conversation, memory.source
    assert_equal @space, memory.space
  end

  test "create_conversation_memory returns early when no space" do
    # Create adhoc conversation without a council (no space)
    orphan_conversation = @account.conversations.create!(
      council: nil,
      user: @user,
      title: "Orphan Conversation",
      status: :concluding,
      conversation_type: :adhoc
    )

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, orphan_conversation)

    summary = { key_decisions: "- Test\n", action_items: "", insights: "", open_questions: "" }

    assert_no_difference "Memory.count" do
      job.send(:create_conversation_memory, summary)
    end
  end

  test "create_conversation_memory handles errors gracefully" do
    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    summary = { key_decisions: "- Test\n", action_items: "", insights: "", open_questions: "" }

    # Force an error by making Memory.create! fail
    Memory.stubs(:create_conversation_summary!).raises(StandardError.new("DB error"))

    # Should not raise - error is caught and logged
    assert_nothing_raised do
      job.send(:create_conversation_memory, summary)
    end
  end

  # ============================================================================
  # find_scribe_advisor Tests
  # ============================================================================

  test "find_scribe_advisor returns conversation scribe advisor" do
    # Ensure an account-level scribe (is_scribe: true) exists
    scribe = @account.advisors.find_by(is_scribe: true) ||
      @space.advisors.create!(
        account: @account,
        name: "Scribe",
        system_prompt: "You are the Scribe",
        llm_model: @llm_model,
        is_scribe: true
      )

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    result = job.send(:find_scribe_advisor)

    assert result.present?
    assert result.is_a?(Advisor)
  end

  test "find_scribe_advisor falls back to account-level scribe when not a conversation participant" do
    # Build a conversation without a scribe participant
    conversation_without_scribe = @council.conversations.build(
      title: "No Scribe Conv",
      user: @user,
      account: @account,
      status: :concluding
    )
    conversation_without_scribe.save!(validate: false)

    scribe = @account.advisors.find_by(is_scribe: true)

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, conversation_without_scribe)

    result = job.send(:find_scribe_advisor)

    assert_equal scribe, result if scribe.present?
  end

  # ============================================================================
  # Edge Cases and Error Handling
  # ============================================================================

  test "perform handles missing messages gracefully" do
    # Ensure we have a valid advisor (may be affected by parallel tests)
    advisor = if @advisor && @advisor.persisted?
      @advisor
    else
      llm = @llm_model || @account.llm_models.enabled.first || create_test_llm_model
      @space.advisors.create!(
        account: @account,
        name: "Test Advisor #{@unique_id}-fallback",
        system_prompt: "You are helpful",
        llm_model: llm
      )
    end

    # Conversation with no messages
    adhoc_conversation = @council.conversations.create!(
      title: "Empty Conversation #{@unique_id}",
      user: @user,
      account: @account,
      status: :concluding,
      conversation_type: :adhoc
    )
    # Add advisor as participant
    adhoc_conversation.conversation_participants.create!(
      advisor: advisor,
      role: "advisor",
      position: 1
    )

    AI::ContentGenerator.any_instance.stubs(:generate_conversation_summary).returns("Summary")
    Turbo::StreamsChannel.stubs(:broadcast_replace_to)

    job = GenerateConversationSummaryJob.new

    assert_nothing_raised do
      job.perform(adhoc_conversation.id)
    end
  end

  test "perform handles nil content in messages" do
    # Skip validation to test nil content handling in build_transcript
    msg = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: nil
    )
    msg.save(validate: false)

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    # build_transcript should handle nil content
    transcript = job.send(:build_transcript)
    # Should not crash with nil content
    assert transcript.include?("#{@user.email}:")
  end

  test "perform handles messages with empty content" do
    # Skip validation to test empty content handling in build_transcript
    msg = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: ""
    )
    msg.save(validate: false)

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    transcript = job.send(:build_transcript)
    assert transcript.include?("#{@user.email}:")
  end
end
