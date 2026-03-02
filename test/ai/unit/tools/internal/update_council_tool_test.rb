# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class UpdateCouncilToolTest < ActiveSupport::TestCase
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
          @tool = UpdateCouncilTool.new
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

        test "name returns update_council" do
          assert_equal "update_council", @tool.name
        end

        test "execute updates council" do
          result = @tool.execute(
            { council_id: @council.id, name: "Updated" },
            { space: @space }
          )

          assert result[:success]
          assert_equal "Updated", @council.reload.name
        end

        test "execute rejects invalid visibility" do
          result = @tool.execute(
            { council_id: @council.id, visibility: "invalid" },
            { space: @space }
          )

          assert_not result[:success]
          assert_match(/visibility must be one of/, result[:error])
        end
      end
    end
  end
end
