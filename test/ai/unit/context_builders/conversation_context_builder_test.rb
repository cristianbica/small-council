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

        # Create advisor
        @advisor = @account.advisors.create!(
          name: "Test Advisor",
          system_prompt: "You are a test advisor",
          space: @space
        )

        @conversation = @account.conversations.create!(
          council: @council,
          user: @user,
          title: "Test Conversation",
          space: @space
        )

        # Add advisor as participant
        @conversation.conversation_participants.create!(
          advisor: @advisor,
          role: :advisor,
          position: 0
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

      test "build includes memory_index with primary summary and knowledge entry fields" do
        summary = @space.memories.create!(
          account: @account,
          title: "Space Summary",
          content: "This is the primary context summary.",
          memory_type: "summary",
          status: "active"
        )

        knowledge = @space.memories.create!(
          account: @account,
          title: "Knowledge Alpha",
          content: "Alpha details for advisor context.",
          memory_type: "knowledge",
          status: "active"
        )

        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        assert context[:memory_index].present?
        assert_equal summary.id, context[:memory_index][:primary_summary][:id]
        assert_equal "Space Summary", context[:memory_index][:primary_summary][:title]

        knowledge_entry = context[:memory_index][:knowledge_entries].find { |entry| entry[:id] == knowledge.id }
        assert_not_nil knowledge_entry
        assert_equal "Knowledge Alpha", knowledge_entry[:title]
        assert knowledge_entry[:summary_excerpt_50_words].present?
      end

      test "build memory_index caps knowledge entries at 8 and excludes archived" do
        isolated_space = @account.spaces.create!(name: "Memory Cap Space")
        isolated_council = @account.councils.create!(name: "Memory Cap Council", user: @user, space: isolated_space)
        isolated_advisor = @account.advisors.create!(
          name: "Isolated Advisor",
          system_prompt: "You are isolated",
          space: isolated_space
        )
        isolated_conversation = @account.conversations.create!(
          council: isolated_council,
          user: @user,
          title: "Memory Cap Conversation",
          space: isolated_space
        )
        isolated_conversation.conversation_participants.create!(
          advisor: isolated_advisor,
          role: :advisor,
          position: 0
        )

        10.times do |i|
          isolated_space.memories.create!(
            account: @account,
            title: "Knowledge #{i}",
            content: "Knowledge content #{i}",
            memory_type: "knowledge",
            status: "active"
          )
        end

        archived = isolated_space.memories.create!(
          account: @account,
          title: "Archived Knowledge",
          content: "Should not appear",
          memory_type: "knowledge",
          status: "archived"
        )

        builder = ConversationContextBuilder.new(isolated_space, isolated_conversation)
        context = builder.build

        entries = context[:memory_index][:knowledge_entries]
        assert_equal 8, entries.size
        refute_includes entries.map { |entry| entry[:id] }, archived.id
      end

      test "build memory_index uses first 50 words with normalized whitespace" do
        words = (1..60).map { |n| "word#{n}" }
        long_content = "  #{words.join("  \n\t")}  "

        memory = @space.memories.create!(
          account: @account,
          title: "Long Knowledge",
          content: long_content,
          memory_type: "knowledge",
          status: "active"
        )

        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        entry = context[:memory_index][:knowledge_entries].find { |item| item[:id] == memory.id }
        excerpt_words = entry[:summary_excerpt_50_words].split(" ")
        assert_equal 50, excerpt_words.length
        assert_equal words.first(50), excerpt_words
      end

      test "build includes related conversations" do
        # Create additional conversations
        other_conversation = @account.conversations.create!(
          council: @council,
          user: @user,
          title: "Other Conversation",
          space: @space
        )

        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        assert context[:related_conversations].is_a?(ActiveRecord::Relation)
        assert_equal 1, context[:related_conversations].count
        assert_equal other_conversation.id, context[:related_conversations].first.id
      end

      test "build includes advisors" do
        # Create a non-scribe advisor and add as participant
        advisor = @space.advisors.create!(
          account: @account,
          name: "Expert Advisor",
          system_prompt: "You are an expert"
        )

        # Add as participant to the conversation
        @conversation.conversation_participants.create!(
          advisor: advisor,
          role: :advisor,
          position: 1
        )

        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        assert context[:advisors].is_a?(Array)
        advisor_ids = context[:advisors].map { |a| a.is_a?(Hash) ? a[:id] : a.id }
        assert_includes advisor_ids, advisor.id
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
        new_conversation = @account.conversations.create!(council: new_council, user: @user, title: "Test", space: new_space)

        builder = ConversationContextBuilder.new(new_space, new_conversation)
        context = builder.build

        # primary_summary should be omitted since it's nil (no summary in new space)
        assert_not context.key?(:primary_summary)
      end

      test "build raises when space is nil and conversation has no council" do
        # Create an adhoc conversation without a council (no way to get space)
        adhoc_conversation = @account.conversations.create!(
          title: "Adhoc Conversation",
          user: @user,
          conversation_type: :adhoc,
          council: nil,
          space: @space
        )

        builder = ConversationContextBuilder.new(nil, adhoc_conversation)
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
            title: "Conversation #{i}",
            space: @space
          )
        end

        builder = ConversationContextBuilder.new(@space, @conversation, conversation_limit: 3)
        context = builder.build

        assert_equal 3, context[:related_conversations].count
      end

      test "build omits council when conversation is not council_meeting" do
        # Create an adhoc conversation
        adhoc_conversation = @account.conversations.create!(
          title: "Adhoc No Council",
          user: @user,
          conversation_type: :adhoc,
          council: nil,
          space: @space
        )
        # Add an advisor participant so validation passes
        adhoc_conversation.conversation_participants.create!(
          advisor: @advisor, role: :advisor, position: 0
        )

        builder = ConversationContextBuilder.new(@space, adhoc_conversation)
        context = builder.build

        assert_not context.key?(:council)
      end

      test "build includes scribe_info when conversation has a scribe" do
        # Add a scribe advisor to the conversation
        provider = @account.providers.create!(name: "ScribeProv", provider_type: "openai", api_key: "k")
        model = provider.llm_models.create!(account: @account, name: "G", identifier: "g-scribe")
        scribe = @account.advisors.create!(
          name: "Test Scribe", system_prompt: "You are the scribe",
          is_scribe: true, space: @space, llm_model: model
        )
        @conversation.conversation_participants.create!(
          advisor: scribe, role: :scribe, position: 10
        )

        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        assert_not_nil context[:scribe]
        assert_equal scribe.id, context[:scribe][:id]
      end

      test "build when conversation has no scribe results in nil scribe (compacted away)" do
        # No scribe participant in @conversation (only advisor from setup)
        builder = ConversationContextBuilder.new(@space, @conversation)
        context = builder.build

        # scribe_info returns nil, ctx.compact removes it
        assert_not context.key?(:scribe)
      end

      test "build succeeds when space is nil but conversation has council with space" do
        # validate_space_context! should return early without raising
        builder = ConversationContextBuilder.new(nil, @conversation)
        context = builder.build

        # Should succeed using council's space
        assert_not_nil context[:space]
      end
    end
  end
end
