require "test_helper"

module RoE
  class ModeratedRoETest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      @user = users(:one)
      set_tenant(@account)

      @space = @account.spaces.first || @account.spaces.create!(name: "General")
      @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

      @provider = @account.providers.create!(
        name: "Test Provider",
        provider_type: "openai",
        api_key: "test-key"
      )
      @llm_model = @provider.llm_models.create!(
        account: @account,
        name: "GPT-4",
        identifier: "gpt-4"
      )

      @advisor1 = @account.advisors.create!(
        name: "Test Advisor One",
        system_prompt: "You are an expert in programming and software development",
        llm_model: @llm_model
      )
      @advisor2 = @account.advisors.create!(
        name: "Test Advisor Two",
        system_prompt: "You specialize in business strategy and management",
        llm_model: @llm_model
      )
      @council.advisors << [ @advisor1, @advisor2 ]

      @conversation = @account.conversations.create!(
        council: @council,
        user: @user,
        title: "Test Conversation",
        rules_of_engagement: :moderated
      )

      @roe = ModeratedRoE.new(@conversation)
    end

    test "@mentions take priority over scoring" do
      @advisor1.update!(name: "Alpha")
      message = create_message("@Alpha please respond about programming")
      responders = @roe.determine_responders(message)
      assert_equal [ @advisor1 ], responders
    end

    test "scores advisors by keyword matching" do
      # Advisor1 has "programming" in system_prompt
      message = create_message("I need help with programming code")
      responders = @roe.determine_responders(message)
      assert_equal [ @advisor1 ], responders
    end

    test "returns advisor with fewest messages when no keywords match" do
      # Create a message from advisor1
      @account.messages.create!(
        conversation: @conversation,
        sender: @advisor1,
        role: "advisor",
        content: "Test message"
      )

      message = create_message("Something generic without keywords")
      responders = @roe.determine_responders(message)
      # Should return advisor2 who has fewer messages
      assert_equal [ @advisor2 ], responders
    end

    test "includes advisor name in scoring" do
      # Advisor1 has "One" in name which matches "one"
      message = create_message("Can someone help me with one specific issue")
      responders = @roe.determine_responders(message)
      assert_equal [ @advisor1 ], responders
    end

    test "returns empty when no advisors" do
      @council.advisors.clear
      message = create_message("Hello")
      responders = @roe.determine_responders(message)
      assert_empty responders
    end

    private

    def create_message(content)
      @account.messages.create!(
        conversation: @conversation,
        sender: @user,
        role: "user",
        content: content
      )
    end
  end
end
