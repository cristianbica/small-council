# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Advisors
      class FetchAdvisorToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          @advisor = @space.advisors.create!(
            account: @account,
            name: "testadvisor",
            system_prompt: "You are a test advisor",
            short_description: "A test advisor",
            is_scribe: false
          )
          @context = { space: @space, user: @user }
        end

        test "read_only is true" do
          assert_equal true, FetchAdvisorTool.read_only
        end

        test "requires_approval is false" do
          assert_equal false, FetchAdvisorTool.requires_approval
        end

        test "execute returns advisor details" do
          tool = FetchAdvisorTool.new(@context)

          result = tool.execute(advisor_id: @advisor.id)

          assert result[:success]
          assert_equal @advisor.id, result[:advisor][:id]
          assert_equal "testadvisor", result[:advisor][:name]
          assert_equal "You are a test advisor", result[:advisor][:system_prompt]
          assert_equal "A test advisor", result[:advisor][:short_description]
        end

        test "execute returns error for blank advisor_id" do
          tool = FetchAdvisorTool.new(@context)

          result = tool.execute(advisor_id: nil)

          assert_equal false, result[:success]
          assert result[:error].include?("required")
        end

        test "execute returns error for non-existent advisor" do
          tool = FetchAdvisorTool.new(@context)

          result = tool.execute(advisor_id: 99999)

          assert_equal false, result[:success]
          assert result[:error].include?("not found")
        end
      end
    end
  end
end
