# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class UpdateAdvisorToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          create_llm_model
          @scribe = @space.scribe_advisor
          @advisor = @space.advisors.create!(
            account: @account,
            name: "Advisor",
            system_prompt: "Prompt"
          )
          @tool = UpdateAdvisorTool.new
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

        test "name returns update_advisor" do
          assert_equal "update_advisor", @tool.name
        end

        test "execute updates advisor" do
          result = @tool.execute(
            { advisor_id: @advisor.id, name: "Updated" },
            { space: @space }
          )

          assert result[:success]
          assert_equal "Updated", @advisor.reload.name
        end

        test "execute rejects missing fields" do
          result = @tool.execute(
            { advisor_id: @advisor.id },
            { space: @space }
          )

          assert_not result[:success]
          assert_match(/No fields to update/, result[:error])
        end

        test "execute denies scribe updates" do
          result = @tool.execute(
            { advisor_id: @scribe.id, name: "Updated" },
            { space: @space }
          )

          assert_not result[:success]
          assert_equal "Cannot update the Scribe advisor", result[:error]
        end
      end
    end
  end
end
