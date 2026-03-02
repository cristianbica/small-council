# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class GetCouncilToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          create_llm_model
          @scribe = @space.scribe_advisor
          @council = @space.councils.create!(
            account: @account,
            user: @user,
            name: "Council",
            visibility: "private"
          )
          @tool = GetCouncilTool.new
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

        test "name returns get_council" do
          assert_equal "get_council", @tool.name
        end

        test "execute returns council details" do
          result = @tool.execute({ council_id: @council.id }, { space: @space })

          assert result[:success]
          assert_equal @council.id, result[:council][:id]
          assert_equal @council.name, result[:council][:name]
        end

        test "execute returns error for missing council" do
          result = @tool.execute({ council_id: 0 }, { space: @space })

          assert_not result[:success]
          assert_match(/Council not found/, result[:error])
        end
      end
    end
  end
end
