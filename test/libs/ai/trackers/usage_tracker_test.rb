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

      test "track creates a usage record when tokens and account are present" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 10, output_price: 20)
        context = OpenStruct.new(account: @account, model: model, message: @message)
        response = OpenStruct.new(input_tokens: 1000, output_tokens: 500)
        result = OpenStruct.new(response: response)

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).track(result)
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

      test "track resolves account through space when account is not directly present" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = OpenStruct.new(space: @space, model: model)
        result = OpenStruct.new(response: OpenStruct.new(input_tokens: 1, output_tokens: 2))

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).track(result)
        end

        assert_equal @account, UsageRecord.order(:id).last.account
      end

      test "track does nothing when tokens are missing" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = OpenStruct.new(account: @account, model: model)

        assert_no_difference "UsageRecord.count" do
          UsageTracker.new(context: context).track(OpenStruct.new(response: OpenStruct.new(input_tokens: nil, output_tokens: 4)))
          UsageTracker.new(context: context).track(OpenStruct.new(response: OpenStruct.new(input_tokens: 3, output_tokens: nil)))
        end
      end

      test "track does nothing when account cannot be resolved" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = OpenStruct.new(model: model)
        result = OpenStruct.new(response: OpenStruct.new(input_tokens: 4, output_tokens: 6))

        assert_no_difference "UsageRecord.count" do
          UsageTracker.new(context: context).track(result)
        end
      end

      test "track rescues and logs errors" do
        context = OpenStruct.new(account: @account, model: nil)
        result = OpenStruct.new(response: OpenStruct.new(input_tokens: 2, output_tokens: 3))

        Rails.logger.expects(:error).with(regexp_matches(/Failed to track usage/))

        assert_no_difference "UsageRecord.count" do
          UsageTracker.new(context: context).track(result)
        end
      end

      test "track supports hash context with symbol key access" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = Object.new
        data = { account: @account, model: model, message: @message }
        context.define_singleton_method(:[]) { |key| data[key] || data[key.to_s] }
        context.define_singleton_method(:key?) { |key| data.key?(key) || data.key?(key.to_s) }
        context.define_singleton_method(:model) { data[:model] }
        result = OpenStruct.new(response: OpenStruct.new(input_tokens: 2, output_tokens: 3))

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).track(result)
        end
      end

      test "track supports hash context with string key access" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = Object.new
        data = { "account" => @account, "model" => model }
        context.define_singleton_method(:[]) { |key| data[key] || data[key.to_s] }
        context.define_singleton_method(:key?) { |key| data.key?(key) || data.key?(key.to_s) }
        context.define_singleton_method(:model) { data["model"] }
        result = OpenStruct.new(response: OpenStruct.new(input_tokens: 2, output_tokens: 3))

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).track(result)
        end
      end

      test "track supports []-only context fallback" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        data = { account: @account, model: model }
        index_context = Object.new
        index_context.define_singleton_method(:[]) do |key|
          data[key] || data[key.to_s]
        end
        index_context.define_singleton_method(:model) { data[:model] }

        result = OpenStruct.new(response: OpenStruct.new(input_tokens: 2, output_tokens: 3))

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: index_context).track(result)
        end
      end

      test "track no-ops when result has no response" do
        context = OpenStruct.new(account: @account, model: OpenStruct.new(provider: OpenStruct.new(provider_type: "openai"), identifier: "gpt-4o", input_price: 0, output_price: 0))

        assert_no_difference "UsageRecord.count" do
          UsageTracker.new(context: context).track(OpenStruct.new(response: nil))
        end
      end

      test "track reads message through [] fallback when reader is absent" do
        provider = OpenStruct.new(provider_type: "openai")
        model = OpenStruct.new(provider: provider, identifier: "gpt-4o", input_price: 0, output_price: 0)
        context = Object.new
        data = { account: @account, model: model, message: @message }
        context.define_singleton_method(:[]) { |key| data[key] || data[key.to_s] }
        context.define_singleton_method(:model) { data[:model] }

        result = OpenStruct.new(response: OpenStruct.new(input_tokens: 4, output_tokens: 5))

        assert_difference "UsageRecord.count", 1 do
          UsageTracker.new(context: context).track(result)
        end

        assert_equal @message, UsageRecord.order(:id).last.message
      end

      test "context_value returns nil for unsupported context objects" do
        tracker = UsageTracker.new(context: Object.new)

        assert_nil tracker.send(:context_value, :account)
      end

      test "context_value prefers public reader before [] access" do
        tracker_context = Object.new
        tracker_context.define_singleton_method(:account) { :reader_value }
        tracker_context.define_singleton_method(:[]) { :index_value }

        tracker = UsageTracker.new(context: tracker_context)

        assert_equal :reader_value, tracker.send(:context_value, :account)
      end
    end
  end
end
