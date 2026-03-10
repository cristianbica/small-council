# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Advisors
      class UpdateAdvisorToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          @advisor = @space.advisors.create!(
            account: @account,
            name: "OriginalName",
            system_prompt: "Original prompt",
            short_description: "Original desc",
            is_scribe: false
          )
          @context = { space: @space, user: @user, account: @account }
        end

        test "requires_approval is true" do
          assert_equal true, UpdateAdvisorTool.requires_approval
        end

        test "read_only is false" do
          assert_equal false, UpdateAdvisorTool.read_only
        end

        test "execute updates advisor name" do
          tool = UpdateAdvisorTool.new(@context)

          result = tool.execute(advisor_id: @advisor.id, name: "NewName")

          assert result[:success]
          # Advisor names are normalized to lowercase
          assert_equal "newname", result[:name]
          @advisor.reload
          assert_equal "newname", @advisor.name
        end

        test "execute updates system_prompt" do
          tool = UpdateAdvisorTool.new(@context)

          result = tool.execute(advisor_id: @advisor.id, system_prompt: "New prompt")

          assert result[:success]
          @advisor.reload
          assert_equal "New prompt", @advisor.system_prompt
        end

        test "execute updates short_description" do
          tool = UpdateAdvisorTool.new(@context)

          result = tool.execute(advisor_id: @advisor.id, short_description: "New desc")

          assert result[:success]
          @advisor.reload
          assert_equal "New desc", @advisor.short_description
        end

        test "execute cannot update scribe advisor" do
          scribe = @space.advisors.create!(
            account: @account,
            name: "Scribe",
            system_prompt: "Scribe prompt",
            is_scribe: true
          )
          tool = UpdateAdvisorTool.new(@context)

          result = tool.execute(advisor_id: scribe.id, name: "NewName")

          assert_equal false, result[:success]
          assert result[:error].include?("Scribe")
        end

        test "execute returns error for missing advisor_id" do
          tool = UpdateAdvisorTool.new(@context)

          # advisor_id is required, so omitting it should raise ArgumentError
          assert_raises(ArgumentError) do
            tool.execute(name: "NewName")
          end
        end

        test "execute returns error for non-existent advisor" do
          tool = UpdateAdvisorTool.new(@context)

          result = tool.execute(advisor_id: 99999, name: "NewName")

          assert_equal false, result[:success]
          assert result[:error].include?("not found")
        end

        test "execute returns error when no fields provided" do
          tool = UpdateAdvisorTool.new(@context)

          result = tool.execute(advisor_id: @advisor.id)

          assert_equal false, result[:success]
          assert result[:error].include?("No fields to update")
        end
      end
    end
  end
end
