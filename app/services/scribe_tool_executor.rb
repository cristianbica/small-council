# Service class to execute Scribe and Advisor tools
# Handles validation, execution, and error handling
class ScribeToolExecutor
  class ToolNotFoundError < StandardError; end
  class ToolValidationError < StandardError; end
  class ToolExecutionError < StandardError; end

  # Registry of all available tools
  SCRIBE_TOOLS = [
    ScribeTools::FinishConversationTool,
    ScribeTools::CreateMemoryTool,
    ScribeTools::QueryMemoriesTool
  ].freeze

  ADVISOR_TOOLS = [
    AdvisorTools::QueryMemoriesTool,
    AdvisorTools::QueryConversationsTool,
    AdvisorTools::ReadConversationTool
  ].freeze

  ALL_TOOLS = (SCRIBE_TOOLS + ADVISOR_TOOLS).freeze

  class << self
    # Get all available tools
    def available_tools(for_scribe: false)
      for_scribe ? SCRIBE_TOOLS : ADVISOR_TOOLS
    end

    # Get all tools as function definitions for AI
    def function_definitions(for_scribe: false)
      available_tools(for_scribe: for_scribe).map do |tool_class|
        tool_class.new.to_function_definition
      end
    end

    # Execute a tool by name
    def execute(tool_name:, params:, context:, for_scribe: false)
      tool_class = find_tool(tool_name, for_scribe: for_scribe)

      unless tool_class
        raise ToolNotFoundError, "Tool '#{tool_name}' not found"
      end

      tool = tool_class.new

      # Validate parameters
      validation_errors = tool.validate_params(params)
      if validation_errors.any?
        raise ToolValidationError, "Validation failed: #{validation_errors.join(', ')}"
      end

      # Execute the tool
      result = tool.execute(params, context)

      # Log the execution
      log_execution(tool_name, params, result, context)

      result
    rescue ToolNotFoundError, ToolValidationError
      raise
    rescue => e
      Rails.logger.error "[ScribeToolExecutor] Tool execution failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      raise ToolExecutionError, "Tool execution failed: #{e.message}"
    end

    # Execute a tool and return formatted result for AI
    def execute_and_format(tool_name:, params:, context:, for_scribe: false)
      result = execute(
        tool_name: tool_name,
        params: params,
        context: context,
        for_scribe: for_scribe
      )

      format_result(result)
    rescue ToolNotFoundError => e
      { error: e.message }
    rescue ToolValidationError => e
      { error: e.message }
    rescue ToolExecutionError => e
      { error: e.message }
    end

    private

    def find_tool(tool_name, for_scribe: false)
      tools = available_tools(for_scribe: for_scribe)
      tools.find { |tool_class| tool_class.new.name == tool_name }
    end

    def format_result(result)
      return result if result.is_a?(Hash)

      {
        success: true,
        data: result
      }
    end

    def log_execution(tool_name, params, result, context)
      Rails.logger.info "[ScribeToolExecutor] Executed: #{tool_name}"
      Rails.logger.info "[ScribeToolExecutor]   Context: convo=#{context.conversation&.id}, space=#{context.space&.id}"
      Rails.logger.info "[ScribeToolExecutor]   Success: #{result[:success]}"
      Rails.logger.info "[ScribeToolExecutor]   Message: #{result[:message]}" if result[:message]

      if result[:success] && result[:data]
        Rails.logger.info "[ScribeToolExecutor]   Data: #{result[:data].to_json[0..200]}..."
      end
    rescue => e
      Rails.logger.error "[ScribeToolExecutor] Logging error: #{e.message}"
    end
  end
end
