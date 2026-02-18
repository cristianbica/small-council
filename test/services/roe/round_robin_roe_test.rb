require "test_helper"

module RoE
  class RoundRobinRoETest < ActiveSupport::TestCase
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
        system_prompt: "You are advisor one",
        llm_model: @llm_model
      )
      @advisor2 = @account.advisors.create!(
        name: "Test Advisor Two",
        system_prompt: "You are advisor two",
        llm_model: @llm_model
      )
      @council.advisors << [ @advisor1, @advisor2 ]

      @conversation = @account.conversations.create!(
        council: @council,
        user: @user,
        title: "Test Conversation",
        rules_of_engagement: :round_robin
      )

      @roe = RoundRobinRoE.new(@conversation)
    end

    test "returns first advisor initially" do
      message = create_message("Hello")
      responders = @roe.determine_responders(message)
      assert_equal [ @advisor1 ], responders
    end

    test "cycles to next advisor" do
      @conversation.mark_advisor_spoken(@advisor1.id)
      message = create_message("Hello again")
      responders = @roe.determine_responders(message)
      assert_equal [ @advisor2 ], responders
    end

    test "wraps back to first" do
      @conversation.mark_advisor_spoken(@advisor2.id)
      message = create_message("Third message")
      responders = @roe.determine_responders(message)
      assert_equal [ @advisor1 ], responders
    end

    test "@mentions take priority over round_robin" do
      @conversation.mark_advisor_spoken(@advisor1.id)
      @advisor1.update!(name: "Alpha")
      message = create_message("@Alpha please respond")
      responders = @roe.determine_responders(message)
      assert_equal [ @advisor1 ], responders
    end

    test "after_response updates last_advisor_id" do
      @roe.after_response(@advisor1)
      assert_equal @advisor1.id.to_s, @conversation.reload.last_advisor_id.to_s
    end

    test "returns empty when no advisors" do
      @council.advisors.clear
      message = create_message("Hello")
      responders = @roe.determine_responders(message)
      assert_empty responders
    end

    test "handles invalid last_advisor_id gracefully" do
      @conversation.mark_advisor_spoken(999999)
      message = create_message("Hello")
      responders = @roe.determine_responders(message)
      assert_equal [ @advisor1 ], responders
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
