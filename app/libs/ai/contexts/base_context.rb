# frozen_string_literal: true

module AI
  module Contexts
    class BaseContext
      attr_reader :args

      def initialize(**args)
        @args = args
      end

      def [](key)
        return args[key] if args.key?(key)
        return args[key.to_s] if args.key?(key.to_s)
        return public_send(key) if respond_to?(key)

        nil
      end

      def key?(key)
        args.key?(key) || args.key?(key.to_s)
      end

      def model
        raise NotImplementedError, "#{self.class} must implement #model"
      end
    end
  end
end
