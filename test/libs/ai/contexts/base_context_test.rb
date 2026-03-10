# frozen_string_literal: true

require "test_helper"

module AI
  module Contexts
    class BaseContextTest < ActiveSupport::TestCase
      class ConcreteContext < BaseContext
        def model
          :mock_model
        end
      end

      test "[] resolves symbol and string keys from args" do
        context = ConcreteContext.new(foo: 1, "bar" => 2)

        assert_equal 1, context[:foo]
        assert_equal 2, context[:bar]
      end

      test "[] falls back to public method and nil when missing" do
        context = ConcreteContext.new

        assert_equal :mock_model, context[:model]
        assert_nil context[:unknown]
      end

      test "key? supports symbol and string keys" do
        context = ConcreteContext.new(foo: 1, "bar" => 2)

        assert_equal true, context.key?(:foo)
        assert_equal true, context.key?(:bar)
        assert_equal false, context.key?(:missing)
      end

      test "model raises when subclass does not implement it" do
        base = BaseContext.new

        assert_raises(NotImplementedError) { base.model }
      end
    end
  end
end
