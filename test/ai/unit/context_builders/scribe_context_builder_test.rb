# frozen_string_literal: true

require "test_helper"

module AI
  module ContextBuilders
    class ScribeContextBuilderTest < ActiveSupport::TestCase
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

        # Create a scribe advisor
        @scribe = @space.advisors.create!(
          account: @account,
          name: "Scribe",
          system_prompt: "You are the scribe"
        )

        # Create memories
        5.times do |i|
          @space.memories.create!(
            account: @account,
            title: "Memory #{i}",
            content: "Content #{i}",
            memory_type: "knowledge",
            status: "active"
          )
        end

        # Create conversations
        3.times do |i|
          @account.conversations.create!(
            council: @council,
            user: @user,
            title: "Conversation #{i}"
          )
        end
      end

      test "build returns complete context" do
        builder = ScribeContextBuilder.new(@space, nil, user: @user, advisor: @scribe)
        context = builder.build

        assert_equal @space, context[:space]
        assert_equal @user, context[:user]
        assert_equal @scribe, context[:advisor]
        assert_equal @space.account.id, context[:account].id
      end

      test "build includes memories" do
        builder = ScribeContextBuilder.new(@space, nil, user: @user, advisor: @scribe)
        context = builder.build

        assert context[:memories].is_a?(ActiveRecord::Relation)
        # Fixtures have 3 active memories, we created 5 more = 8 total
        assert context[:memories].count >= 5
      end

      test "build includes recent conversations" do
        builder = ScribeContextBuilder.new(@space, nil, user: @user, advisor: @scribe)
        context = builder.build

        assert context[:recent_conversations].is_a?(ActiveRecord::Relation)
        assert_equal 3, context[:recent_conversations].count
      end

      test "build includes advisors" do
        # Create a non-scribe advisor
        advisor = @space.advisors.create!(
          account: @account,
          name: "Expert Advisor",
          system_prompt: "You are an expert"
        )

        builder = ScribeContextBuilder.new(@space, nil, user: @user, advisor: @scribe)
        context = builder.build

        assert context[:advisors].is_a?(ActiveRecord::Relation)
        assert context[:advisors].include?(advisor)
        assert context[:advisors].exclude?(@scribe) # Scribe is filtered out
      end

      test "build includes primary summary when available" do
        summary = @space.memories.create!(
          account: @account,
          title: "Primary Summary",
          content: "Space summary",
          memory_type: "summary",
          status: "active"
        )

        builder = ScribeContextBuilder.new(@space, nil, user: @user, advisor: @scribe)
        context = builder.build

        assert_equal summary.id, context[:primary_summary].id
      end

      test "build works without optional options" do
        builder = ScribeContextBuilder.new(@space)
        context = builder.build

        assert_equal @space, context[:space]
        assert_nil context[:user]
        assert_nil context[:advisor]
      end

      test "build raises when space is nil" do
        builder = ScribeContextBuilder.new(nil)
        assert_raises(ArgumentError) do
          builder.build
        end
      end

      test "build respects memory_limit option" do
        builder = ScribeContextBuilder.new(@space, nil, user: @user, advisor: @scribe, memory_limit: 3)
        context = builder.build

        assert_equal 3, context[:memories].count
      end

      test "build respects conversation_limit option" do
        builder = ScribeContextBuilder.new(@space, nil, user: @user, advisor: @scribe, conversation_limit: 2)
        context = builder.build

        assert_equal 2, context[:recent_conversations].count
      end

      test "build omits nil values from context" do
        # Use a new space that doesn't have fixtures
        new_space = @account.spaces.create!(name: "Empty Space")
        builder = ScribeContextBuilder.new(new_space)
        context = builder.build

        # Keys with nil values should be removed by compact
        assert_not context.key?(:user)
        assert_not context.key?(:advisor)
        assert_not context.key?(:primary_summary)
      end

      test "build includes all context keys when options provided" do
        summary = @space.memories.create!(
          account: @account,
          title: "Primary Summary",
          content: "Space summary",
          memory_type: "summary",
          status: "active"
        )

        builder = ScribeContextBuilder.new(@space, nil, user: @user, advisor: @scribe)
        context = builder.build

        assert context.key?(:space)
        assert context.key?(:user)
        assert context.key?(:advisor)
        assert context.key?(:memories)
        assert context.key?(:recent_conversations)
        assert context.key?(:advisors)
        assert context.key?(:primary_summary)
        assert context.key?(:account)
      end
    end
  end
end
