# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class CreateMemoryToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = @account.users.first || @account.users.create!(email: "test@example.com", password: "password123")
          @advisor = @space.advisors.create!(
            account: @account,
            name: "Test Advisor",
            system_prompt: "You are a test advisor"
          )
          @tool = CreateMemoryTool.new
        end

        test "name returns create_memory" do
          assert_equal "create_memory", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("memory")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:title)
          assert params[:properties].key?(:content)
          assert params[:properties].key?(:memory_type)
          assert params[:properties].key?(:tags)
          assert_includes params[:required], :title
          assert_includes params[:required], :content
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({ title: "Test", content: "Content" }, {})
          end
          assert_match(/Missing required context: space/, error.message)
        end

        test "execute returns error without title" do
          result = @tool.execute({ content: "Content" }, { space: @space })
          assert_not result[:success]
          assert_equal "title is required", result[:error]
        end

        test "execute returns error without content" do
          result = @tool.execute({ title: "Test" }, { space: @space })
          assert_not result[:success]
          assert_equal "content is required", result[:error]
        end

        test "execute creates memory with required fields" do
          result = @tool.execute(
            { title: "New Memory", content: "This is the content" },
            { space: @space, user: @user }
          )

          assert result[:success]
          assert result[:memory_id].present?
          assert_equal "New Memory", result[:title]
          assert_equal "knowledge", result[:memory_type]

          memory = Memory.find(result[:memory_id])
          assert_equal "New Memory", memory.title
          assert_equal "This is the content", memory.content
          assert_equal "knowledge", memory.memory_type
          assert_equal "active", memory.status
          assert_equal @user, memory.created_by
        end

        test "execute creates memory with advisor as creator" do
          result = @tool.execute(
            { title: "Advisor Memory", content: "Advisor created this" },
            { space: @space, advisor: @advisor }
          )

          assert result[:success]
          memory = Memory.find(result[:memory_id])
          assert_equal @advisor, memory.created_by
        end

        test "execute creates memory with specified type" do
          result = @tool.execute(
            {
              title: "Summary Memory",
              content: "This is a summary",
              memory_type: "summary"
            },
            { space: @space, user: @user }
          )

          assert result[:success]
          memory = Memory.find(result[:memory_id])
          assert_equal "summary", memory.memory_type
        end

        test "execute defaults to knowledge for invalid type" do
          result = @tool.execute(
            {
              title: "Test Memory",
              content: "Content",
              memory_type: "invalid_type"
            },
            { space: @space, user: @user }
          )

          assert result[:success]
          memory = Memory.find(result[:memory_id])
          assert_equal "knowledge", memory.memory_type
        end

        test "execute creates memory with tags" do
          result = @tool.execute(
            {
              title: "Tagged Memory",
              content: "Content with tags",
              tags: [ "project", "important" ]
            },
            { space: @space, user: @user }
          )

          assert result[:success]
          memory = Memory.find(result[:memory_id])
          assert_equal [ "project", "important" ], memory.metadata["tags"]
        end

        test "execute creates memory with empty tags when not provided" do
          result = @tool.execute(
            { title: "Untagged Memory", content: "Content" },
            { space: @space, user: @user }
          )

          assert result[:success]
          memory = Memory.find(result[:memory_id])
          assert_equal [], memory.metadata["tags"] || []
        end

        test "execute creates version record" do
          result = @tool.execute(
            { title: "Versioned Memory", content: "Content" },
            { space: @space, user: @user }
          )

          memory = Memory.find(result[:memory_id])
          assert_equal 1, memory.versions.count
          assert_equal "Initial creation", memory.versions.first.change_reason
        end
      end
    end
  end
end
