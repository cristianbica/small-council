# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class ListAdvisorsToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          create_llm_model
          @scribe = @space.scribe_advisor
          @tool = ListAdvisorsTool.new

          @space.advisors.where(is_scribe: false).destroy_all

          3.times do |i|
            @space.advisors.create!(
              account: @account,
              name: "Advisor #{i + 1}",
              system_prompt: "Prompt #{i + 1}"
            )
          end
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

        test "name returns list_advisors" do
          assert_equal "list_advisors", @tool.name
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:limit)
          assert params[:properties].key?(:offset)
        end

        test "execute lists advisors without scribe by default" do
          result = @tool.execute({}, { space: @space })

          assert result[:success]
          assert_equal 3, result[:count]
          assert result[:advisors].none? { |a| a[:is_scribe] }
        end

        test "execute includes scribe when requested" do
          result = @tool.execute({ include_scribe: true }, { space: @space })

          assert result[:success]
          assert result[:advisors].any? { |a| a[:is_scribe] }
        end

        test "execute enforces pagination" do
          result = @tool.execute({ limit: 2, offset: 1 }, { space: @space })

          assert result[:success]
          assert_equal 2, result[:count]
          assert_equal 2, result[:limit]
          assert_equal 1, result[:offset]
        end
      end
    end
  end
end
