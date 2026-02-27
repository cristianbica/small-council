# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class ListConversationsToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = @account.users.first || @account.users.create!(email: "test@example.com", password: "password123")
          @council = @space.councils.first || @space.councils.create!(name: "Test Council", account: @account, user: @user)
          @tool = ListConversationsTool.new

          # Create test conversations
          5.times do |i|
            @council.conversations.create!(
              account: @account,
              user: @user,
              title: "Conversation #{i + 1}",
              status: i.even? ? "active" : "resolved"
            )
          end

          # Create another council with conversations
          @other_council = @space.councils.create!(name: "Other Council", account: @account, user: @user)
          @other_council.conversations.create!(
            account: @account,
            user: @user,
            title: "Other Conversation"
          )
        end

        test "name returns list_conversations" do
          assert_equal "list_conversations", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("conversations")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:status)
          assert params[:properties].key?(:council_id)
          assert params[:properties].key?(:limit)
          assert params[:properties].key?(:offset)
          assert_empty params[:required]
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({}, {})
          end
          assert_match(/Missing required context: space/, error.message)
        end

        test "execute lists all conversations in space" do
          result = @tool.execute({}, { space: @space })

          assert result[:success]
          assert_equal 6, result[:total_count]  # 5 + 1 from other council
          assert result[:conversations].length <= 10
        end

        test "execute filters by status" do
          result = @tool.execute({ status: "active" }, { space: @space })

          assert result[:success]
          # Should only have active conversations
          assert result[:conversations].all? { |c| c[:status] == "active" }
        end

        test "execute filters by resolved status" do
          result = @tool.execute({ status: "resolved" }, { space: @space })

          assert result[:success]
          assert result[:conversations].all? { |c| c[:status] == "resolved" }
        end

        test "execute filters by council_id" do
          result = @tool.execute({ council_id: @other_council.id }, { space: @space })

          assert result[:success]
          assert_equal 1, result[:count]
          assert_equal "Other Conversation", result[:conversations].first[:title]
        end

        test "execute ignores invalid status filter" do
          result = @tool.execute({ status: "invalid_status" }, { space: @space })

          assert result[:success]
          assert_equal 6, result[:count]  # Returns all
        end

        test "execute respects limit parameter" do
          result = @tool.execute({ limit: 3 }, { space: @space })

          assert result[:success]
          assert_equal 3, result[:count]
          assert_equal 3, result[:limit]
        end

        test "execute enforces max limit" do
          result = @tool.execute({ limit: 50 }, { space: @space })

          assert result[:success]
          assert result[:limit] <= 20
        end

        test "execute enforces min limit" do
          result = @tool.execute({ limit: 0 }, { space: @space })

          assert result[:success]
          assert_equal 10, result[:limit]
        end

        test "execute respects offset for pagination" do
          result = @tool.execute({ limit: 2, offset: 2 }, { space: @space })

          assert result[:success]
          assert_equal 2, result[:count]
          assert_equal 2, result[:offset]
        end

        test "execute returns has_more when more results available" do
          result = @tool.execute({ limit: 2 }, { space: @space })

          assert result[:success]
          assert result[:has_more]
        end

        test "execute returns has_more false when no more results" do
          result = @tool.execute({ limit: 10 }, { space: @space })

          assert result[:success]
          assert_not result[:has_more]
        end

        test "execute formats conversation data correctly" do
          result = @tool.execute({ limit: 1 }, { space: @space })

          conversation = result[:conversations].first
          assert conversation[:id].present?
          assert conversation[:title].present?
          assert conversation[:status].present?
          assert conversation[:council].present?
          assert conversation.key?(:message_count)
          assert conversation.key?(:rules_of_engagement)
        end

        test "execute returns empty results for empty space" do
          empty_space = @account.spaces.create!(name: "Empty Space")

          result = @tool.execute({}, { space: empty_space })

          assert result[:success]
          assert_equal 0, result[:count]
          assert_empty result[:conversations]
        end
      end
    end
  end
end
