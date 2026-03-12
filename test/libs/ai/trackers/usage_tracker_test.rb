# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  module Trackers
    class UsageTrackerTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @space = spaces(:one)
        @message = messages(:one)
      end

      test "track via callback creates a usage record when tokens and account are present" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 10, output_price: 20)
        context = OpenStruct.new(account: @account, model: model, message: @message)
        response = OpenStruct.new(input_tokens: 1000, output_tokens: 500)

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).send(:track_response, response)
        end

        record = UsageRecord.order(:id).last
        assert_equal @account, record.account
        assert_equal "openai", record.provider
        assert_equal "gpt-4o", record.model
        assert_equal 1000, record.input_tokens
        assert_equal 500, record.output_tokens
        assert_equal @message, record.message
        assert_equal 2, record.cost_cents
      end

      test "track via callback resolves account through space when account is not directly present" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = OpenStruct.new(space: @space, model: model)
        response = OpenStruct.new(input_tokens: 1, output_tokens: 2)

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).send(:track_response, response)
        end

        assert_equal @account, UsageRecord.order(:id).last.account
      end

      test "track via callback does nothing when tokens are missing" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = OpenStruct.new(account: @account, model: model)

        assert_no_difference "UsageRecord.count" do
          UsageTracker.new(context: context).send(:track_response, OpenStruct.new(input_tokens: nil, output_tokens: 4))
          UsageTracker.new(context: context).send(:track_response, OpenStruct.new(input_tokens: 3, output_tokens: nil))
        end
      end

      test "track via callback does nothing when account cannot be resolved" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = OpenStruct.new(model: model)
        response = OpenStruct.new(input_tokens: 4, output_tokens: 6)

        assert_no_difference "UsageRecord.count" do
          UsageTracker.new(context: context).send(:track_response, response)
        end
      end

      test "track via callback rescues and logs errors" do
        context = OpenStruct.new(account: @account, model: nil)
        response = OpenStruct.new(input_tokens: 2, output_tokens: 3)

        Rails.logger.expects(:error).with(regexp_matches(/Failed to track usage/))

        assert_no_difference "UsageRecord.count" do
          UsageTracker.new(context: context).send(:track_response, response)
        end
      end

      test "track via callback supports hash context with symbol key access" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = Object.new
        data = { account: @account, model: model, message: @message }
        context.define_singleton_method(:[]) { |key| data[key] || data[key.to_s] }
        context.define_singleton_method(:key?) { |key| data.key?(key) || data.key?(key.to_s) }
        context.define_singleton_method(:model) { data[:model] }
        response = OpenStruct.new(input_tokens: 2, output_tokens: 3)

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).send(:track_response, response)
        end
      end

      test "track via callback supports hash context with string key access" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = Object.new
        data = { "account" => @account, "model" => model }
        context.define_singleton_method(:[]) { |key| data[key] || data[key.to_s] }
        context.define_singleton_method(:key?) { |key| data.key?(key) || data.key?(key.to_s) }
        context.define_singleton_method(:model) { data["model"] }
        response = OpenStruct.new(input_tokens: 2, output_tokens: 3)

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).send(:track_response, response)
        end
      end

      test "track via callback supports []-only context fallback" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        data = { account: @account, model: model }
        index_context = Object.new
        index_context.define_singleton_method(:[]) do |key|
          data[key] || data[key.to_s]
        end
        index_context.define_singleton_method(:model) { data[:model] }

        response = OpenStruct.new(input_tokens: 2, output_tokens: 3)

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: index_context).send(:track_response, response)
        end
      end

      test "track via callback no-ops when response is nil" do
        context = OpenStruct.new(account: @account, model: OpenStruct.new(provider: OpenStruct.new(provider_type: "openai"), identifier: "gpt-4o", input_price: 0, output_price: 0))

        assert_no_difference "UsageRecord.count" do
          UsageTracker.new(context: context).send(:track_response, nil)
        end
      end

      test "track via callback reads message through [] fallback when reader is absent" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = Object.new
        data = { account: @account, model: model, message: @message }
        context.define_singleton_method(:[]) { |key| data[key] || data[key.to_s] }
        context.define_singleton_method(:model) { data[:model] }

        response = OpenStruct.new(input_tokens: 4, output_tokens: 5)

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).send(:track_response, response)
        end

        assert_equal @message, UsageRecord.order(:id).last.message
      end

      test "track method creates usage record from result" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 10, output_price: 20)
        context = OpenStruct.new(account: @account, model: model, message: @message)
        response = OpenStruct.new(input_tokens: 10, output_tokens: 5)
        result = OpenStruct.new(response: response)

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).track(result)
        end

        record = UsageRecord.order(:id).last
        assert_equal @account, record.account
        assert_equal "openai", record.provider
        assert_equal "gpt-4o", record.model
        assert_equal 10, record.input_tokens
        assert_equal 5, record.output_tokens
        assert_equal @message, record.message
      end
    end
  end
end
