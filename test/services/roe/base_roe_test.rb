require "test_helper"
require_relative "../../../app/services/roe"

module RoE
  class BaseRoETest < ActiveSupport::TestCase
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
        rules_of_engagement: :round_robin
      )
    end

    test "factory creates correct RoE class for each mode" do
      {
        "round_robin" => RoundRobinRoE,
        "moderated" => ModeratedRoE,
        "on_demand" => OnDemandRoE,
        "silent" => SilentRoE,
        "consensus" => ConsensusRoE
      }.each do |mode, expected_class|
        @conversation.update!(rules_of_engagement: mode)
        roe = Factory.create(@conversation)
        assert_instance_of expected_class, roe
      end
    end

    test "factory defaults to SilentRoE for unknown mode" do
      # Stub to test fallback
      def @conversation.rules_of_engagement
        "unknown_mode"
      end
      roe = Factory.create(@conversation)
      assert_instance_of SilentRoE, roe
    end

    test "base RoE raises NotImplementedError for determine_responders" do
      base = BaseRoE.new(@conversation)
      message = create_message("Hello")
      assert_raises(NotImplementedError) do
        base.determine_responders(message)
      end
    end

    test "parse_mentions returns empty for blank content" do
      roe = RoundRobinRoE.new(@conversation)
      assert_empty roe.send(:parse_mentions, nil)
      assert_empty roe.send(:parse_mentions, "")
      assert_empty roe.send(:parse_mentions, "   ")
    end

    test "parse_mentions finds advisors by name with underscores" do
      @advisor1.update!(name: "Test Advisor")
      roe = RoundRobinRoE.new(@conversation)

      message = create_message("Hey @Test_Advisor, help me out")
      mentioned = roe.send(:parse_mentions, message.content)

      assert_equal [ @advisor1 ], mentioned
    end

    test "parse_mentions finds advisors by exact name" do
      @advisor1.update!(name: "Alpha")
      roe = RoundRobinRoE.new(@conversation)

      message = create_message("@Alpha please respond")
      mentioned = roe.send(:parse_mentions, message.content)

      assert_equal [ @advisor1 ], mentioned
    end

    test "parse_mentions handles multiple mentions" do
      @advisor1.update!(name: "Advisor One")
      @advisor2.update!(name: "Advisor Two")
      roe = RoundRobinRoE.new(@conversation)

      message = create_message("@Advisor_One and @Advisor_Two please help")
      mentioned = roe.send(:parse_mentions, message.content)

      assert_equal 2, mentioned.count
      assert_includes mentioned, @advisor1
      assert_includes mentioned, @advisor2
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
