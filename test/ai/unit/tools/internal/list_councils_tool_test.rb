# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class ListCouncilsToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          create_llm_model
          @scribe = @space.scribe_advisor
          @tool = ListCouncilsTool.new

          @space.councils.destroy_all
          @space.councils.create!(account: @account, user: @user, name: "Council A", visibility: "private")
          @space.councils.create!(account: @account, user: @user, name: "Council B", visibility: "shared")
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

        test "name returns list_councils" do
          assert_equal "list_councils", @tool.name
        end

        test "execute lists councils" do
          result = @tool.execute({}, { space: @space })

          assert result[:success]
          assert_equal 2, result[:count]
        end

        test "execute filters by visibility" do
          result = @tool.execute({ visibility: "shared" }, { space: @space })

          assert result[:success]
          assert_equal 1, result[:count]
          assert_equal "Council B", result[:councils].first[:name]
        end
      end
    end
  end
end
