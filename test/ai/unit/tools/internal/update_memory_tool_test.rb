# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class UpdateMemoryToolTest < ActiveSupport::TestCase
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
          @tool = UpdateMemoryTool.new

          @memory = @space.memories.create!(
            account: @account,
            title: "Original Title",
            content: "Original content here.",
            memory_type: "knowledge",
            status: "active",
            metadata: { "tags" => [ "original" ] },
            created_by: @user
          )
        end

        test "name returns update_memory" do
          assert_equal "update_memory", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("Update")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:memory_id)
          assert params[:properties].key?(:title)
          assert params[:properties].key?(:content)
          assert params[:properties].key?(:tags)
          assert params[:properties].key?(:change_reason)
          assert_includes params[:required], :memory_id
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({ memory_id: @memory.id, title: "New" }, {})
          end
          assert_match(/Missing required context: space/, error.message)
        end

        test "execute returns error without memory_id" do
          result = @tool.execute({ title: "New" }, { space: @space })
          assert_not result[:success]
          assert_equal "memory_id is required", result[:error]
        end

        test "execute returns error when no fields to update" do
          result = @tool.execute({ memory_id: @memory.id }, { space: @space })

          assert_not result[:success]
          assert_match(/No fields to update/, result[:error])
        end

        test "execute returns error for nonexistent memory" do
          result = @tool.execute(
            { memory_id: 999999, title: "New Title" },
            { space: @space }
          )

          assert_not result[:success]
          assert_match(/not found/, result[:error])
        end

        test "execute updates title only" do
          result = @tool.execute(
            { memory_id: @memory.id, title: "Updated Title" },
            { space: @space, user: @user }
          )

          assert result[:success]
          assert_equal "Updated Title", result[:title]

          @memory.reload
          assert_equal "Updated Title", @memory.title
          assert_equal "Original content here.", @memory.content  # Unchanged
          assert_equal [ "original" ], @memory.metadata["tags"]  # Unchanged
        end

        test "execute updates content only" do
          result = @tool.execute(
            { memory_id: @memory.id, content: "Updated content here." },
            { space: @space, user: @user }
          )

          assert result[:success]

          @memory.reload
          assert_equal "Original Title", @memory.title  # Unchanged
          assert_equal "Updated content here.", @memory.content
        end

        test "execute updates tags only" do
          result = @tool.execute(
            { memory_id: @memory.id, tags: [ "updated", "tags" ] },
            { space: @space, user: @user }
          )

          assert result[:success]

          @memory.reload
          assert_equal [ "updated", "tags" ], @memory.metadata["tags"]
        end

        test "execute updates multiple fields at once" do
          result = @tool.execute(
            {
              memory_id: @memory.id,
              title: "New Title",
              content: "New content",
              tags: [ "new" ]
            },
            { space: @space, advisor: @advisor }
          )

          assert result[:success]

          @memory.reload
          assert_equal "New Title", @memory.title
          assert_equal "New content", @memory.content
          assert_equal [ "new" ], @memory.metadata["tags"]
          assert_equal @advisor, @memory.updated_by
        end

        test "execute creates version record before updating" do
          original_version_count = @memory.versions.count

          result = @tool.execute(
            { memory_id: @memory.id, title: "Updated Title", change_reason: "Fixed typo" },
            { space: @space, user: @user }
          )

          assert result[:success]
          assert result[:version_created]
          assert_equal "Fixed typo", result[:change_reason]

          @memory.reload
          assert_equal original_version_count + 1, @memory.versions.count

          version = @memory.versions.ordered.first
          assert_equal "Original Title", version.title
          assert_equal "Fixed typo", version.change_reason
        end

        test "execute uses default change reason when not provided" do
          result = @tool.execute(
            { memory_id: @memory.id, title: "Updated Title" },
            { space: @space, user: @user }
          )

          assert result[:success]
          assert_equal "Updated via AI tool", result[:change_reason]

          version = @memory.versions.ordered.first
          assert_equal "Updated via AI tool", version.change_reason
        end

        test "execute only finds memories in the context space" do
          other_space = @account.spaces.create!(name: "Other Space")

          result = @tool.execute(
            { memory_id: @memory.id, title: "Hacked" },
            { space: other_space, user: @user }
          )

          assert_not result[:success]
          assert_match(/not found/, result[:error])

          # Original memory should be unchanged
          @memory.reload
          assert_equal "Original Title", @memory.title
        end
      end
    end
  end
end
