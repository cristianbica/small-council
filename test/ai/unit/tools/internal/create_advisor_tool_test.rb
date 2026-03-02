# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class CreateAdvisorToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          create_llm_model
          @scribe = @space.scribe_advisor
          @tool = CreateAdvisorTool.new
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

        test "name returns create_advisor" do
          assert_equal "create_advisor", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:name)
          assert params[:properties].key?(:system_prompt)
          assert_includes params[:required], :name
          assert_includes params[:required], :system_prompt
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({ name: "Name", system_prompt: "Prompt" }, {})
          end
          assert_match(/Missing required context:/, error.message)
          assert_match(/space/, error.message)
        end

        test "execute creates advisor" do
          result = @tool.execute(
            { name: "New Advisor", system_prompt: "Prompt" },
            { space: @space }
          )

          assert result[:success]
          advisor = Advisor.find(result[:advisor_id])
          assert_equal "New Advisor", advisor.name
          assert_equal @space, advisor.space
          assert_equal @account, advisor.account
          assert_not advisor.is_scribe
        end
      end
    end
  end
end
