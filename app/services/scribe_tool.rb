# Base class for all Scribe tools
# Scribe tools have full access to modify conversations, memories, and trigger actions
class ScribeTool
  attr_reader :name, :description, :parameters

  def initialize
    @name = tool_name
    @description = tool_description
    @parameters = tool_parameters
  end

  # Override in subclasses
  def tool_name
    raise NotImplementedError, "Subclasses must define tool_name"
  end

  # Override in subclasses
  def tool_description
    raise NotImplementedError, "Subclasses must define tool_description"
  end

  # Override in subclasses - returns hash of parameter definitions
  # Example: { conversation_id: { type: "string", required: true } }
  def tool_parameters
    {}
  end

  # Override in subclasses - performs the tool action
  # @param params [Hash] The validated parameters
  # @param context [ToolExecutionContext] Context including conversation, space, advisor, etc.
  # @return [Hash] Result with :success (boolean) and optional :message, :data
  def execute(params, context)
    raise NotImplementedError, "Subclasses must implement execute(params, context)"
  end

  # Validate parameters against the tool's parameter schema
  def validate_params(params)
    errors = []

    tool_parameters.each do |param_name, config|
      value = params[param_name.to_s] || params[param_name.to_sym]

      if config[:required] && (value.nil? || value.to_s.empty?)
        errors << "#{param_name} is required"
        next
      end

      next if value.nil?

      # Type validation
      case config[:type]
      when "string"
        unless value.is_a?(String)
          errors << "#{param_name} must be a string"
        end
      when "integer"
        unless value.is_a?(Integer) || value.to_s.match?(/^\d+$/)
          errors << "#{param_name} must be an integer"
        end
      when "boolean"
        unless [ true, false, "true", "false" ].include?(value)
          errors << "#{param_name} must be a boolean"
        end
      end

      # Enum validation
      if config[:enum] && !config[:enum].include?(value)
        errors << "#{param_name} must be one of: #{config[:enum].join(', ')}"
      end
    end

    errors
  end

  # Build the tool definition for AI function calling
  def to_function_definition
    {
      type: "function",
      function: {
        name: name,
        description: description,
        parameters: {
          type: "object",
          properties: build_parameter_properties,
          required: build_required_params
        }
      }
    }
  end

  private

  def build_parameter_properties
    properties = {}

    tool_parameters.each do |param_name, config|
      prop = { type: config[:type] || "string" }
      prop[:description] = config[:description] if config[:description]
      prop[:enum] = config[:enum] if config[:enum]

      properties[param_name] = prop
    end

    properties
  end

  def build_required_params
    tool_parameters
      .select { |_, config| config[:required] }
      .map(&:first)
  end
end
