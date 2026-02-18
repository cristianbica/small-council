require "test_helper"

module RoE
  class ConsensusRoETest < ActiveSupport::TestCase
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
        rules_of_engagement: :consensus
      )

      @roe = ConsensusRoE.new(@conversation)
    end

    test "returns all advisors" do
      message = create_message("Hello everyone")
      responders = @roe.determine_responders(message)
      assert_equal 2, responders.count
      assert_includes responders, @advisor1
      assert_includes responders, @advisor2
    end

    test "@mentions override returns mentioned advisors only" do
      @advisor1.update!(name: "Alpha")
      message = create_message("@Alpha please respond")
      responders = @roe.determine_responders(message)
      assert_equal [ @advisor1 ], responders
    end

    test "empty council returns empty" do
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
