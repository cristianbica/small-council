# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class UnassignAdvisorFromCouncilToolTest < ActiveSupport::TestCase
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
          @council.advisors << @advisor
          @tool = UnassignAdvisorFromCouncilTool.new
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

        test "name returns unassign_advisor_from_council" do
          assert_equal "unassign_advisor_from_council", @tool.name
        end

        test "execute unassigns advisor from council" do
          result = @tool.execute(
            { council_id: @council.id, advisor_id: @advisor.id },
            { space: @space }
          )

          assert result[:success]
          assert_not @council.advisors.reload.include?(@advisor)
        end

        test "execute denies unassigning scribe" do
          @council.ensure_scribe_assigned
          @council.reload

          result = @tool.execute(
            { council_id: @council.id, advisor_id: @scribe.id },
            { space: @space }
          )

          assert_not result[:success]
          assert_equal "Cannot unassign the Scribe advisor", result[:error]
        end

        test "execute scopes council to space" do
          other_account = accounts(:two)
          other_space = other_account.spaces.first || other_account.spaces.create!(name: "Other Space")
          other_user = other_account.users.first || other_account.users.create!(email: "other@example.com", password: "password123")
          other_council = other_space.councils.create!(
            account: other_account,
            user: other_user,
            name: "Other Council"
          )

          result = @tool.execute(
            { council_id: other_council.id, advisor_id: @advisor.id },
            { space: @space }
          )

          assert_not result[:success]
          assert_match(/Council not found/, result[:error])
        end
      end
    end
  end
end
