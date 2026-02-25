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
        llm_model: @llm_model,
        space: @space
      )
      @advisor2 = @account.advisors.create!(
        name: "Test Advisor Two",
        system_prompt: "You specialize in business strategy and management",
        llm_model: @llm_model,
        space: @space
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

    test "scribe advisor takes priority in moderated mode" do
      # Create a scribe advisor
      scribe = @account.advisors.create!(
        name: "The Scribe",
        system_prompt: "You are the scribe who moderates discussions",
        llm_model: @llm_model,
        space: @space
      )
      @council.advisors << scribe

      message = create_message("I need help with programming")
      responders = @roe.determine_responders(message)
      # Should return scribe, not the keyword-matching advisor
      assert_equal [ scribe ], responders
    end

    test "scrib advisor name variant is detected" do
      # Create a scrib advisor (alternative spelling)
      scrib = @account.advisors.create!(
        name: "Council Scrib",
        system_prompt: "You are the scrib who moderates discussions",
        llm_model: @llm_model,
        space: @space
      )
      @council.advisors << scrib

      message = create_message("I need help with programming")
      responders = @roe.determine_responders(message)
      # Should return scrib
      assert_equal [ scrib ], responders
    end

    test "creates scribe when none exists and uses it for moderation" do
      message = create_message("I need help with programming")

      # No scribe exists in council initially (space may have auto-created one)
      assert_nil @council.advisors.find_by("LOWER(name) LIKE ? OR LOWER(name) LIKE ?", "%scribe%", "%scrib%")

      responders = @roe.determine_responders(message)

      # Scribe should be returned as responder (from space)
      assert responders.any? { |r| r.scribe? }, "Scribe should be returned as responder"
      assert_equal 1, responders.count
    end

    test "@mentions take priority over scribe selection" do
      # Create a scribe advisor
      scribe = @account.advisors.create!(
        name: "The Scribe",
        system_prompt: "You are the scribe who moderates discussions",
        llm_model: @llm_model,
        space: @space
      )
      @council.advisors << scribe

      @advisor1.update!(name: "Alpha")
      message = create_message("@Alpha please respond about programming")
      responders = @roe.determine_responders(message)
      # @mentions should still take priority over scribe
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
