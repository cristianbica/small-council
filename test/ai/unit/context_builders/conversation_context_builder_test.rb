# frozen_string_literal: true

require "test_helper"

module AI
  module ContextBuilders
    class ConversationContextBuilderTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)

        @space = @account.spaces.first || @account.spaces.create!(name: "Test Space")
        @user = users(:one)

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

        # Create memories
        3.times do |i|
          @space.memories.create!(
            account: @account,
            title: "Memory #{i}",
            content: "Content #{i}",
            memory_type: "knowledge",
            status: "active"
          )
        end
      end

      test "build returns complete context" do
        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        assert_equal @space, context[:space]
        assert_equal @conversation, context[:conversation]
        assert_equal @conversation.user, context[:user]
        assert_equal @council.id, context[:council].id
        assert_equal @space.account.id, context[:account].id
      end

      test "build includes memories" do
        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        assert context[:memories].is_a?(ActiveRecord::Relation)
        # Fixtures have 3 active memories, we created 3 more = 6 total
        assert context[:memories].count >= 3
      end

      test "build includes related conversations" do
        # Create additional conversations
        other_conversation = @account.conversations.create!(
          council: @council,
          user: @user,
          title: "Other Conversation"
        )

        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        assert context[:related_conversations].is_a?(ActiveRecord::Relation)
        assert_equal 1, context[:related_conversations].count
        assert_equal other_conversation.id, context[:related_conversations].first.id
      end

      test "build includes advisors" do
        # Create a non-scribe advisor
        advisor = @space.advisors.create!(
          account: @account,
          name: "Expert Advisor",
          system_prompt: "You are an expert"
        )

        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        assert context[:advisors].is_a?(ActiveRecord::Relation)
        assert context[:advisors].include?(advisor)
      end

      test "build includes primary summary when available" do
        summary = @space.memories.create!(
          account: @account,
          title: "Primary Summary",
          content: "Space summary",
          memory_type: "summary",
          status: "active"
        )

        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        assert_equal summary.id, context[:primary_summary].id
      end

      test "build omits nil values" do
        # Use a new space that doesn't have the summary fixture
        new_space = @account.spaces.create!(name: "Empty Space")
        new_council = @account.councils.create!(name: "New Council", user: @user, space: new_space)
        new_conversation = @account.conversations.create!(council: new_council, user: @user, title: "Test")

        builder = ConversationContextBuilder.new(new_space, new_conversation)
        context = builder.build

        # primary_summary should be omitted since it's nil (no summary in new space)
        assert_not context.key?(:primary_summary)
      end

      test "build raises when space is nil" do
        builder = ConversationContextBuilder.new(nil, @conversation)
        assert_raises(ArgumentError) do
          builder.build
        end
      end

      test "build raises when conversation is nil" do
        builder = ConversationContextBuilder.new(@space, nil)
        assert_raises(ArgumentError) do
          builder.build
        end
      end

      test "build respects memory_limit option" do
        # Create more memories
        10.times do |i|
          @space.memories.create!(
            account: @account,
            title: "Extra Memory #{i}",
            content: "Extra content",
            memory_type: "knowledge",
            status: "active"
          )
        end

        builder = ConversationContextBuilder.new(@space, @conversation, memory_limit: 5)
        context = builder.build

        assert_equal 5, context[:memories].count
      end

      test "build respects conversation_limit option" do
        # Create more conversations
        5.times do |i|
          @account.conversations.create!(
            council: @council,
            user: @user,
            title: "Conversation #{i}"
          )
        end

        builder = ConversationContextBuilder.new(@space, @conversation, conversation_limit: 3)
        context = builder.build

        assert_equal 3, context[:related_conversations].count
      end
    end
  end
end
