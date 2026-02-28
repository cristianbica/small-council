# app/services/commands/base_command.rb
module Commands
  class BaseCommand
    attr_reader :args, :errors

    def initialize(args)
      @args = args
      @errors = []
    end

    def valid?
      validate
      @errors.empty?
    end

    def execute(conversation:, user:)
      raise NotImplementedError
    end

    protected

    def validate
      raise NotImplementedError
    end
  end
end
