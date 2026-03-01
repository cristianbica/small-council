# frozen_string_literal: true

require "test_helper"

module AI
  module ContextBuilders
    class BaseContextBuilderTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)

        @space = @account.spaces.first || @account.spaces.create!(name: "Test Space")
        @user = users(:one)

        # Create a council and conversation
        @council = @account.councils.create!(
          name: "Test Council",
          user: @user,
          space: @space
        )
        @conversation = @account.conversations.create!(
          council: @council,
          user: @user,
          title: "Test Conversation"
        )

        # Create some memories
        5.times do |i|
          @space.memories.create!(
            account: @account,
            title: "Memory #{i}",
            content: "Content #{i}",
            memory_type: "knowledge",
            status: "active"
          )
        end

        # Create an archived memory (should not appear)
        @space.memories.create!(
          account: @account,
          title: "Archived Memory",
          content: "Archived content",
          memory_type: "knowledge",
          status: "archived"
        )
      end

      test "initializes with space and conversation" do
        builder = TestBuilder.new(@space, @conversation)
        assert_equal @space, builder.instance_variable_get(:@space)
        assert_equal @conversation, builder.instance_variable_get(:@conversation)
      end

      test "initializes with space only" do
        builder = TestBuilder.new(@space)
        assert_equal @space, builder.instance_variable_get(:@space)
        assert_nil builder.instance_variable_get(:@conversation)
      end

      test "initializes with options" do
        builder = TestBuilder.new(@space, @conversation, memory_limit: 5, custom: true)
        assert_equal({ memory_limit: 5, custom: true }, builder.instance_variable_get(:@options))
      end

    test "recent_memories returns active memories only" do
      builder = TestBuilder.new(@space)
      memories = builder.send(:recent_memories)

      # Fixtures have 3 active memories in space(:one), we created 5 more
      # But we also created 1 archived which shouldn't appear
      assert memories.all? { |m| m.status == "active" }
      assert memories.none? { |m| m.title == "Archived Memory" }
      assert memories.count >= 5  # At least our 5 created memories
    end

      test "recent_memories respects limit option" do
        builder = TestBuilder.new(@space, nil, memory_limit: 3)
        memories = builder.send(:recent_memories)

        assert_equal 3, memories.count
      end

      test "recent_memories uses default limit when not specified" do
        # Create more memories to test default limit
        10.times do |i|
          @space.memories.create!(
            account: @account,
            title: "Extra Memory #{i}",
            content: "Extra content #{i}",
            memory_type: "knowledge",
            status: "active"
          )
        end

        builder = TestBuilder.new(@space)
        memories = builder.send(:recent_memories)

        assert_equal 10, memories.count
      end

      test "recent_memories returns empty array when space is nil" do
        builder = TestBuilder.new(nil)
        assert_empty builder.send(:recent_memories)
      end

      test "recent_conversations returns conversations from space" do
        # Create additional conversations
        3.times do |i|
          @account.conversations.create!(
            council: @council,
            user: @user,
            title: "Conversation #{i}"
          )
        end

        builder = TestBuilder.new(@space, @conversation)
        conversations = builder.send(:recent_conversations)

        # Should exclude the current conversation
        assert_equal 3, conversations.count
        assert conversations.none? { |c| c.id == @conversation.id }
      end

      test "recent_conversations includes all conversations when no current conversation" do
        @account.conversations.create!(
          council: @council,
          user: @user,
          title: "Another Conversation"
        )

        builder = TestBuilder.new(@space)
        conversations = builder.send(:recent_conversations)

        # Should include the conversation created in setup and the new one
        assert_equal 2, conversations.count
      end

      test "recent_conversations returns empty array when space is nil" do
        builder = TestBuilder.new(nil)
        assert_empty builder.send(:recent_conversations)
      end

      test "space_advisors returns non-scribe advisors" do
        # Create a scribe advisor with is_scribe flag
        @space.advisors.create!(
          account: @account,
          name: "Scribe",
          system_prompt: "You are the scribe",
          is_scribe: true
        )

        # Create a regular advisor
        regular_advisor = @space.advisors.create!(
          account: @account,
          name: "Expert Advisor",
          system_prompt: "You are an expert"
        )

        builder = TestBuilder.new(@space)
        advisors = builder.send(:space_advisors)

        assert_equal 1, advisors.count
        assert_equal regular_advisor.id, advisors.first.id
      end

      test "primary_summary returns summary memory" do
        summary = @space.memories.create!(
          account: @account,
          title: "Primary Summary",
          content: "Space summary content",
          memory_type: "summary",
          status: "active"
        )

        builder = TestBuilder.new(@space)
        result = builder.send(:primary_summary)

        assert_equal summary.id, result.id
      end

      test "primary_summary returns nil when no summary exists" do
        # Use a new space that doesn't have the summary fixture
        new_space = @account.spaces.create!(name: "Empty Space")
        builder = TestBuilder.new(new_space)
        assert_nil builder.send(:primary_summary)
      end

      test "validate_conversation! raises when conversation is nil" do
        builder = TestBuilder.new(@space)
        assert_raises(ArgumentError) do
          builder.send(:validate_conversation!)
        end
      end

      test "space_advisors returns empty array when space is nil" do
        builder = TestBuilder.new(nil)
        assert_empty builder.send(:space_advisors)
      end

      test "conversation_advisors returns empty array when conversation is nil" do
        builder = TestBuilder.new(@space)
        assert_empty builder.send(:conversation_advisors)
      end

      test "effective_space returns space when space is set" do
        builder = TestBuilder.new(@space, @conversation)
        assert_equal @space, builder.send(:effective_space)
      end

      test "effective_space returns council space when space is nil and conversation is council_meeting" do
        builder = TestBuilder.new(nil, @conversation)
        assert_equal @space, builder.send(:effective_space)
      end

      test "effective_space returns nil when both space and conversation council are nil" do
        adhoc_conv = @account.conversations.create!(
          user: @user, title: "Adhoc No Space", conversation_type: "adhoc"
        )
        builder = TestBuilder.new(nil, adhoc_conv)
        assert_nil builder.send(:effective_space)
      end

      test "roe_description returns open description for open roe_type" do
        # Create advisor so conversation update passes validation
        regular_advisor = @space.advisors.create!(
          account: @account, name: "ROE Test Advisor", system_prompt: "Expert"
        )
        @conversation.conversation_participants.create!(advisor: regular_advisor, role: "advisor")
        @conversation.update!(roe_type: "open")
        builder = TestBuilder.new(@space, @conversation)
        desc = builder.send(:roe_description)
        assert_includes desc, "@mentioned"
      end

      test "roe_description returns consensus description for consensus roe_type" do
        regular_advisor = @space.advisors.create!(
          account: @account, name: "Consensus Advisor", system_prompt: "Expert"
        )
        @conversation.conversation_participants.create!(advisor: regular_advisor, role: "advisor")
        @conversation.update!(roe_type: "consensus")
        builder = TestBuilder.new(@space, @conversation)
        desc = builder.send(:roe_description)
        assert_includes desc, "agreement"
      end

      test "roe_description returns brainstorming description for brainstorming roe_type" do
        regular_advisor = @space.advisors.create!(
          account: @account, name: "Brain Advisor", system_prompt: "Expert"
        )
        @conversation.conversation_participants.create!(advisor: regular_advisor, role: "advisor")
        @conversation.update!(roe_type: "brainstorming")
        builder = TestBuilder.new(@space, @conversation)
        desc = builder.send(:roe_description)
        assert_includes desc, "ideas"
      end

      test "roe_description returns nil when no conversation" do
        builder = TestBuilder.new(@space)
        assert_nil builder.send(:roe_description)
      end

      test "roe_description returns unknown description for unknown roe_type" do
        # Bypass enum by setting raw value
        @conversation.update_column(:roe_type, "unknown_custom_type")
        builder = TestBuilder.new(@space, @conversation)
        desc = builder.send(:roe_description)
        assert_includes desc, "Unknown"
      end

      test "conversation_thread includes replies with sender name" do
        # Create a user message
        user_msg = @conversation.messages.create!(
          account: @account, sender: @user, role: "user", content: "Hello"
        )
        # Create a reply from an advisor (has .name method)
        provider = @account.providers.create!(name: "ThreadProv", provider_type: "openai", api_key: "k")
        model = provider.llm_models.create!(account: @account, name: "G", identifier: "g-t")
        advisor = @account.advisors.create!(
          name: "Thread Advisor", system_prompt: "Expert", space: @space, llm_model: model
        )
        reply = @conversation.messages.create!(
          account: @account, sender: advisor, role: "advisor", content: "Reply",
          in_reply_to_id: user_msg.id
        )

        builder = TestBuilder.new(@space, @conversation)
        thread = builder.send(:conversation_thread)

        assert thread.any? { |m| m[:message_id] == user_msg.id }
        root = thread.find { |m| m[:message_id] == user_msg.id }
        assert_equal "user", root[:role]
        assert_equal "user", root[:sender_name]
        assert reply.in_reply_to_id == user_msg.id
        reply_entry = root[:replies].find { |entry| entry[:parent_id] == user_msg.id }
        assert_equal "Thread Advisor", reply_entry[:sender_name]
      end
    end

    # Test builder for testing base class methods
    class TestBuilder < BaseContextBuilder
      def build
        # Minimal implementation for testing
        {}
      end
    end
  end
end
