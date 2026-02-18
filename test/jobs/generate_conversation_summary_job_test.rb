require "test_helper"

class GenerateConversationSummaryJobTest < ActiveJob::TestCase
  def setup
    @account = accounts(:one)
    set_tenant(@account)

    @user = @account.users.first
    @space = @account.spaces.first
    @council = @space.councils.create!(
      name: "Test Council",
      user: @user,
      account: @account
    )
    @conversation = @council.conversations.create!(
      title: "Test Conversation",
      user: @user,
      account: @account,
      status: :concluding
    )
  end

  test "should generate structured summary with fallback on AI error" do
    # Mock the AI client to raise an error
    AiClient.any_instance.stubs(:generate_response).raises(StandardError, "API Error")

    job = GenerateConversationSummaryJob.new
    job.instance_variable_set(:@conversation, @conversation)

    result = job.send(:generate_summary, "Test transcript content")

    assert result[:key_decisions].include?("AI generation failed")
    assert result[:action_items].include?("AI generation failed")
    assert result[:insights].include?("AI generation failed")
    assert result[:open_questions].include?("AI generation failed")
  end

  test "parse_structured_summary should extract sections correctly" do
    job = GenerateConversationSummaryJob.new

    content = <<~CONTENT
      ## Key Decisions
      - Decision one
      - Decision two

      ## Action Items
      - Action one

      ## Insights
      - Insight here

      ## Open Questions
      - Question one
    CONTENT

    result = job.send(:parse_structured_summary, content)

    assert result[:key_decisions].include?("Decision one")
    assert result[:action_items].include?("Action one")
    assert result[:insights].include?("Insight here")
    assert result[:open_questions].include?("Question one")
    assert_equal content, result[:raw_summary]
  end

  test "parse_structured_summary should handle missing sections" do
    job = GenerateConversationSummaryJob.new

    content = "Some random text without proper sections"
    result = job.send(:parse_structured_summary, content)

    assert_equal "- None identified\n", result[:key_decisions]
    assert_equal "- None identified\n", result[:action_items]
    assert_equal "- None identified\n", result[:insights]
    assert_equal "- None identified\n", result[:open_questions]
  end

  test "extract_section should find sections with various formats" do
    job = GenerateConversationSummaryJob.new

    content = "## Key Decisions\n- Item 1\n- Item 2\n\n## Action Items\n- Action 1"
    section = job.send(:extract_section, content, "Key Decisions")

    assert section.include?("Item 1")
    assert section.include?("Item 2")
    assert_not section.include?("Action 1")
  end
end
