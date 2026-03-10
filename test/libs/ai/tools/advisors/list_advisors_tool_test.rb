# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Advisors
      class ListAdvisorsToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          @advisor1 = @space.advisors.create!(
            account: @account,
            name: "advisor1",
            system_prompt: "Prompt 1",
            is_scribe: false
          )
          @advisor2 = @space.advisors.create!(
            account: @account,
            name: "advisor2",
            system_prompt: "Prompt 2",
            is_scribe: false
          )
          @scribe = @space.advisors.create!(
            account: @account,
            name: "scribe",
            system_prompt: "Scribe prompt",
            is_scribe: true
          )
          @context = { space: @space, user: @user }
        end

        test "read_only is true" do
          assert_equal true, ListAdvisorsTool.read_only
        end

        test "requires_approval is false" do
          assert_equal false, ListAdvisorsTool.requires_approval
        end

        test "execute returns paginated advisors" do
          tool = ListAdvisorsTool.new(@context)

          result = tool.execute

          assert result[:success]
          assert result[:advisors].length >= 2
          assert result[:total_count] >= 2
          assert_equal 10, result[:limit]
        end

        test "execute excludes scribe by default" do
          tool = ListAdvisorsTool.new(@context)

          result = tool.execute

          assert result[:success]
          assert result[:advisors].none? { |a| a[:is_scribe] }
        end

        test "execute includes scribe when requested" do
          tool = ListAdvisorsTool.new(@context)

          result = tool.execute(include_scribe: true)

          assert result[:success]
          assert result[:advisors].any? { |a| a[:is_scribe] }
        end

        test "execute respects limit" do
          tool = ListAdvisorsTool.new(@context)

          result = tool.execute(limit: 1)

          assert result[:success]
          assert_equal 1, result[:count]
        end

        test "execute enforces max limit of 20" do
          tool = ListAdvisorsTool.new(@context)

          result = tool.execute(limit: 50)

          assert result[:success]
          assert_equal 20, result[:limit]
        end

        test "execute with offset" do
          tool = ListAdvisorsTool.new(@context)

          result = tool.execute(offset: 1)

          assert result[:success]
          assert_equal 1, result[:offset]
        end
      end
    end
  end
end
