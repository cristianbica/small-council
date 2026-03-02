# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class AssignAdvisorToCouncilToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          create_llm_model
          @scribe = @space.scribe_advisor
          @advisor = @space.advisors.create!(
            account: @account,
            name: "Advisor",
            system_prompt: "Prompt"
          )
          @council = @space.councils.create!(
            account: @account,
            user: @user,
            name: "Council"
          )
          @tool = AssignAdvisorToCouncilTool.new
        end

        def create_llm_model
          provider = @account.providers.create!(name: "Test", provider_type: "openai", api_key: "key")
          provider.llm_models.create!(
            account: @account,
            name: "GPT-4",
            identifier: "gpt-4",
            enabled: true
          )
        end

        test "name returns assign_advisor_to_council" do
          assert_equal "assign_advisor_to_council", @tool.name
        end

        test "execute assigns advisor to council" do
          result = @tool.execute(
            { council_id: @council.id, advisor_id: @advisor.id, position: 1 },
            { space: @space }
          )

          assert result[:success]
          join = @council.council_advisors.find_by(advisor: @advisor)
          assert_equal 1, join.position
        end

        test "execute denies duplicates" do
          @council.advisors << @advisor

          result = @tool.execute(
            { council_id: @council.id, advisor_id: @advisor.id },
            { space: @space }
          )

          assert_not result[:success]
          assert_equal "Advisor already assigned to council", result[:error]
        end

        test "execute scopes advisor to space" do
          other_account = accounts(:two)
          other_space = other_account.spaces.first || other_account.spaces.create!(name: "Other Space")
          other_advisor = other_space.advisors.create!(
            account: other_account,
            name: "Other Advisor",
            system_prompt: "Prompt"
          )

          result = @tool.execute(
            { council_id: @council.id, advisor_id: other_advisor.id },
            { space: @space }
          )

          assert_not result[:success]
          assert_match(/Advisor not found/, result[:error])
        end
      end
    end
  end
end
