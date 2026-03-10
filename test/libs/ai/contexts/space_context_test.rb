# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  module Contexts
    class SpaceContextTest < ActiveSupport::TestCase
      test "model uses enabled default llm model when present" do
        default_model = OpenStruct.new(enabled?: true)
        account = OpenStruct.new(default_llm_model: default_model, llm_models: OpenStruct.new(enabled: OpenStruct.new(free: [ :unused ])))
        context = SpaceContext.new(account: account)

        assert_equal default_model, context.model
      end

      test "model falls back to first enabled free model" do
        fallback_model = OpenStruct.new(identifier: "free")
        account = OpenStruct.new(
          default_llm_model: OpenStruct.new(enabled?: false),
          llm_models: OpenStruct.new(enabled: OpenStruct.new(free: [ fallback_model ]))
        )
        context = SpaceContext.new(account: account)

        assert_equal fallback_model, context.model
      end
    end
  end
end
