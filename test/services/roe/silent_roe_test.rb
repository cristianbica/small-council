require "test_helper"

module RoE
  class SilentRoETest < ActiveSupport::TestCase
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
        llm_model: @llm_model,
        space: @space
      )
      @advisor2 = @account.advisors.create!(
        name: "Test Advisor Two",
        system_prompt: "You are advisor two",
        llm_model: @llm_model,
        space: @space
      )
      @council.advisors << [ @advisor1, @advisor2 ]

      @conversation = @account.conversations.create!(
        council: @council,
        user: @user,
        title: "Test Conversation",
        rules_of_engagement: :silent
      )

      @roe = SilentRoE.new(@conversation)
    end

    test "returns empty normally" do
      message = create_message("Hello")
      responders = @roe.determine_responders(message)
      assert_empty responders
    end

    test "returns mentioned advisors (override)" do
      @advisor1.update!(name: "Alpha")
      message = create_message("@Alpha please respond")
      responders = @roe.determine_responders(message)
      assert_equal [ @advisor1 ], responders
    end

    test "returns multiple mentioned advisors" do
      @advisor1.update!(name: "Advisor One")
      @advisor2.update!(name: "Advisor Two")
      message = create_message("@Advisor_One and @Advisor_Two please help")
      responders = @roe.determine_responders(message)
      assert_equal 2, responders.count
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
