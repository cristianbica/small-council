# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class GetAdvisorToolTest < ActiveSupport::TestCase
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
          @tool = GetAdvisorTool.new
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

        test "name returns get_advisor" do
          assert_equal "get_advisor", @tool.name
        end

        test "execute returns error when advisor missing" do
          result = @tool.execute({ advisor_id: 0 }, { space: @space })

          assert_not result[:success]
          assert_match(/Advisor not found/, result[:error])
        end

        test "execute returns advisor details" do
          result = @tool.execute({ advisor_id: @advisor.id }, { space: @space })

          assert result[:success]
          assert_equal @advisor.id, result[:advisor][:id]
          assert_equal @advisor.name, result[:advisor][:name]
        end
      end
    end
  end
end
