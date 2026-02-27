# frozen_string_literal: true


module AI
  module Tools
    module External
      # Browse external websites for information
      class BrowseWebTool < BaseTool
        def description
          "Browse the web for recent information. Use this for current events, fact-checking, or gathering information from external sources."
        end

        def parameters
          {
            type: "object",
            properties: {
              url: {
                type: "string",
                description: "URL to browse (e.g., https://example.com)"
              },
              extract_text: {
                type: "boolean",
                description: "Extract readable text (true) or return raw content (false). Default: true"
              }
            },
            required: [ :url ]
          }
        end

        def execute(arguments = {}, context = {})
          url = arguments[:url] || arguments["url"]
          extract_text = arguments[:extract_text] || arguments["extract_text"]

          if url.blank?
            return {
              success: false,
              error: "URL is required"
            }
          end

          # Normalize extract_text default
          extract_text = true if extract_text.nil?

          # Security: Block potentially dangerous URLs first
          block_reason = blocked_url_reason(url)
          if block_reason
            return {
              success: false,
              error: block_reason
            }
          end

          Rails.logger.info "[BrowseWebTool] Fetching URL: #{url}"

          browser = WebBrowserService.new(timeout: 15)
          result = browser.fetch(url, extract_text: extract_text)

          if result[:success]
            # Limit content length for the response
            content_preview = result[:content].to_s[0...5000]
            if result[:content].to_s.length > 5000
              content_preview += "\n\n[... #{result[:content].length - 5000} more characters ...]"
            end

            {
              success: true,
              message: "Successfully fetched '#{result[:title]}' from #{result[:url]}",
              url: result[:url],
              title: result[:title],
              content: content_preview,
              content_type: result[:content_type],
              content_length: result[:content]&.length || 0,
              truncated: result[:content].to_s.length > 5000
            }
          else
            {
              success: false,
              error: "Failed to fetch URL: #{result[:error]}"
            }
          end
        rescue => e
          Rails.logger.error "[BrowseWebTool] Error: #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")

          {
            success: false,
            error: "An error occurred while browsing: #{e.message}"
          }
        end

        private

        def blocked_url_reason(url)
          # Check for invalid format (no protocol at all)
          unless url.match?(/\A\w+:\/\//i)
            return "Invalid URL format. URLs must start with http:// or https://"
          end

          # Block non-http/https protocols
          unless url.match?(/\Ahttps?:\/\//i)
            return "This URL is blocked for security reasons. Only standard web pages are allowed."
          end

          blocked_patterns = [
            /localhost/i,
            /127\.\d+\.\d+\.\d+/,
            /192\.168\./,
            /10\.\d+\.\d+\.\d+/,
            /172\.(1[6-9]|2\d|3[01])\./,
            /\.internal$/i,
            /\.local$/i,
            /\.corp$/i
          ]

          if blocked_patterns.any? { |pattern| url.match?(pattern) }
            return "This URL is blocked for security reasons. Only standard web pages are allowed."
          end

          nil
        end
      end
    end
  end
end
