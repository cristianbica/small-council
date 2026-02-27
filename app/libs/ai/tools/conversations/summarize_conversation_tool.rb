# frozen_string_literal: true


module AI
  module Tools
    module Conversations
      # Get a summary of the conversation so far
      # This tool allows AI agents to understand the conversation context
      class SummarizeConversationTool < BaseTool
        def description
          "Get a summary of the conversation so far. Useful to understand context and previous discussion."
        end

        def parameters
          {
            type: "object",
            properties: {
              style: {
                type: "string",
                enum: [ "brief", "detailed", "bullet_points" ],
                description: "Style of summary: brief (1-2 sentences), detailed (paragraph), or bullet_points"
              },
              message_limit: {
                type: "integer",
                description: "Number of recent messages to include in summary (default: 50, max: 100)",
                minimum: 1,
                maximum: 100
              }
            },
            required: [ :style ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :conversation)

          style = arguments[:style] || arguments["style"] || "brief"
          message_limit = arguments[:message_limit] || arguments["message_limit"]

          conversation = context[:conversation]

          # Get recent messages
          limit = message_limit.to_i
          limit = 50 if limit < 1
          limit = 100 if limit > 100

          messages = conversation.messages.chronological.limit(limit)

          if messages.empty?
            return {
              success: true,
              summary: "No messages in conversation yet.",
              style: style,
              message_count: 0
            }
          end

          summary = generate_summary(messages, style, conversation)

          {
            success: true,
            summary: summary,
            style: style,
            message_count: messages.count,
            conversation_id: conversation.id,
            conversation_title: conversation.title
          }
        end

        private

        def generate_summary(messages, style, conversation)
          case style.to_s
          when "brief"
            generate_brief_summary(messages, conversation)
          when "detailed"
            generate_detailed_summary(messages, conversation)
          when "bullet_points"
            generate_bullet_points(messages, conversation)
          else
            generate_brief_summary(messages, conversation)
          end
        end

        def generate_brief_summary(messages, conversation)
          participants = messages.map { |m| m.sender.try(:name) || m.sender.try(:email) || "Unknown" }.uniq.compact
          first_message = messages.first
          last_message = messages.last

          "Conversation '#{conversation.title}' with #{participants.join(', ')}. " \
          "Started #{first_message.created_at.strftime('%Y-%m-%d')}. " \
          "#{messages.count} messages total. " \
          "Latest topic: #{last_message.content.truncate(100)}"
        end

        def generate_detailed_summary(messages, conversation)
          participants = messages.map { |m| m.sender.try(:name) || m.sender.try(:email) || "Unknown" }.uniq.compact
          topics = extract_topics(messages)

          "This is a conversation titled '#{conversation.title}' in the '#{conversation.council&.name}' council. " \
          "The discussion involves #{participants.join(', ')}. " \
          "There have been #{messages.count} messages exchanged. " \
          "Key topics discussed: #{topics.join(', ')}. " \
          "The conversation is currently #{conversation.status}."
        end

        def generate_bullet_points(messages, conversation)
          participants = messages.map { |m| m.sender.try(:name) || m.sender.try(:email) || "Unknown" }.uniq.compact
          key_points = extract_key_points(messages)

          points = [
            "Conversation: #{conversation.title}",
            "Council: #{conversation.council&.name}",
            "Participants: #{participants.join(', ')}",
            "Total messages: #{messages.count}",
            "Status: #{conversation.status}"
          ]

          points += key_points.map { |p| "• #{p}" }

          points.join("\n")
        end

        def extract_topics(messages)
          # Simple topic extraction based on message content keywords
          messages.map { |m| m.content }
                  .join(" ")
                  .downcase
                  .scan(/\b(?:project|task|meeting|decision|budget|plan|issue|question|update)\w*\b/)
                  .uniq
                  .first(5)
        end

        def extract_key_points(messages)
          # Extract what seem to be key points (questions, decisions, mentions)
          key_messages = messages.select do |m|
            content = m.content.downcase
            content.include?("?") ||
              content.include?("decided") ||
              content.include?("agreed") ||
              content.include?("@")
          end

          key_messages.last(5).map { |m| "#{m.sender.try(:name) || m.sender.try(:email) || 'Unknown'}: #{m.content.truncate(80)}" }
        end
      end
    end
  end
end
