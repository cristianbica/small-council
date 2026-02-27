# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class ReadMemoryToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = @account.users.first || @account.users.create!(email: "test@example.com", password: "password123")
          @tool = ReadMemoryTool.new

          @memory = @space.memories.create!(
            account: @account,
            title: "Test Memory",
            content: "This is the full content of the memory. It contains detailed information.",
            memory_type: "knowledge",
            status: "active",
            metadata: { "key" => "value", "tags" => [ "test", "example" ] },
            created_by: @user
          )
        end

        test "name returns read_memory" do
          assert_equal "read_memory", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("memory")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:memory_id)
          assert_includes params[:required], :memory_id
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({ memory_id: 1 }, {})
          end
          assert_match(/Missing required context: space/, error.message)
        end

        test "execute returns error without memory_id" do
          result = @tool.execute({}, { space: @space })
          assert_not result[:success]
          assert_equal "memory_id is required", result[:error]
        end

        test "execute returns full memory details" do
          result = @tool.execute({ memory_id: @memory.id }, { space: @space })

          assert result[:success]
          assert result[:memory].present?

          memory_data = result[:memory]
          assert_equal @memory.id, memory_data[:id]
          assert_equal "Test Memory", memory_data[:title]
          assert_equal "This is the full content of the memory. It contains detailed information.", memory_data[:content]
          assert_equal "knowledge", memory_data[:type]
          assert_equal "active", memory_data[:status]
          assert_equal [ "test", "example" ], memory_data[:tags]
          assert_equal({ "key" => "value", "tags" => [ "test", "example" ] }, memory_data[:metadata])
          assert_equal @user.email, memory_data[:created_by]
        end

        test "execute returns error for nonexistent memory" do
          result = @tool.execute({ memory_id: 999999 }, { space: @space })

          assert_not result[:success]
          assert_match(/not found/, result[:error])
        end

        test "execute only finds memories in the context space" do
          other_space = @account.spaces.create!(name: "Other Space")

          result = @tool.execute({ memory_id: @memory.id }, { space: other_space })

          assert_not result[:success]
          assert_match(/not found/, result[:error])
        end

        test "execute handles memory from different space" do
          other_space = @account.spaces.create!(name: "Other Space")
          other_memory = other_space.memories.create!(
            account: @account,
            title: "Other Memory",
            content: "Other content",
            memory_type: "knowledge",
            status: "active",
            created_by: @user
          )

          # Can find when using correct space
          result = @tool.execute({ memory_id: other_memory.id }, { space: other_space })
          assert result[:success]
          assert_equal "Other Memory", result[:memory][:title]

          # Cannot find when using wrong space
          result = @tool.execute({ memory_id: other_memory.id }, { space: @space })
          assert_not result[:success]
        end

        test "execute handles conversation source" do
          council = @space.councils.create!(name: "Test Council", account: @account, user: @user)
          conversation = council.conversations.create!(
            account: @account,
            user: @user,
            title: "Test Conversation"
          )

          memory_with_source = @space.memories.create!(
            account: @account,
            source: conversation,
            title: "Conversation Memory",
            content: "From conversation",
            memory_type: "conversation_notes",
            status: "active",
            created_by: @user
          )

          result = @tool.execute({ memory_id: memory_with_source.id }, { space: @space })

          assert result[:success]
          assert_equal "Conversation: Test Conversation", result[:memory][:source]
        end
      end
    end
  end
end
