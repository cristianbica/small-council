# frozen_string_literal: true


module AI
  module Tools
    module Conversations
      # Ask another advisor a question
      # This tool allows AI agents to get input from other advisors in the council
      class AskAdvisorTool < BaseTool
        def description
          "Ask a specific advisor a question. Use this to get input from other advisors in the council."
        end

        def parameters
          {
            type: "object",
            properties: {
              advisor_name: {
                type: "string",
                description: "Name of the advisor to ask"
              },
              question: {
                type: "string",
                description: "The question to ask the advisor"
              }
            },
            required: [ :advisor_name, :question ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space, :conversation)

          advisor_name = arguments[:advisor_name] || arguments["advisor_name"]
          question = arguments[:question] || arguments["question"]

          if advisor_name.blank?
            return { success: false, error: "advisor_name is required" }
          end

          if question.blank?
            return { success: false, error: "question is required" }
          end

          space = context[:space]
          conversation = context[:conversation]

          advisor = find_advisor(space, advisor_name)

          unless advisor
            available_advisors = space.advisors.map(&:name).join(", ")
            return {
              success: false,
              error: "Advisor '#{advisor_name}' not found",
              available_advisors: available_advisors
            }
          end

          # Don't ask yourself
          current_advisor = context[:advisor]
          if current_advisor && current_advisor.id == advisor.id
            return {
              success: false,
              error: "Cannot ask yourself a question"
            }
          end

          # Create mention message
          message = create_mention_message(context, advisor, question)

          # Enqueue job to generate response
          enqueue_response_job(advisor, message, conversation)

          {
            success: true,
            message: "Asked #{advisor.name} to respond",
            advisor_id: advisor.id,
            advisor_name: advisor.name,
            message_id: message.id
          }
        end

        private

        def find_advisor(space, name)
          return nil if name.blank?

          # Try exact match first
          advisor = space.advisors.find { |a| a.name.downcase == name.downcase }
          return advisor if advisor

          # Try partial match
          space.advisors.find { |a| a.name.downcase.include?(name.downcase) }
        end

        def create_mention_message(context, advisor, question)
          sender = context[:user] || context[:advisor]

          context[:conversation].messages.create!(
            account: context[:conversation].account,
            sender: sender,
            role: "user",
            content: "@#{advisor.name} #{question}",
            status: "complete"
          )
        end

        def enqueue_response_job(advisor, message, conversation)
          GenerateAdvisorResponseJob.perform_later(
            advisor_id: advisor.id,
            conversation_id: conversation.id,
            message_id: message.id
          )
        end
      end
    end
  end
end
