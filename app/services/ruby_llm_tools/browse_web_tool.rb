module RubyLLMTools
  class BrowseWebTool < RubyLLM::Tool
    description "Fetch and read content from a web page. Use this to research topics, check documentation, verify facts, or gather information from the internet. Returns the page title and extracted text content."

    param :url,
      desc: "The URL to fetch (e.g., https://example.com or just example.com). Must be a valid web address starting with http:// or https://",
      type: :string

    param :extract_text,
      desc: "Whether to extract readable text (true) or return raw HTML (false). Default: true",
      type: :boolean

    def execute(url: nil, extract_text: true)
      if url.blank?
        return {
          success: false,
          message: "URL cannot be blank. Please provide a valid web address starting with http:// or https://"
        }
      end

      # Security: Validate URL format
      unless url.match?(/\Ahttps?:\/\//i)
        return {
          success: false,
          message: "Invalid URL format. URLs must start with http:// or https://"
        }
      end

      # Security: Block potentially dangerous URLs
      if blocked_url?(url)
        return {
          success: false,
          message: "This URL is blocked for security reasons. Only standard web pages are allowed."
        }
      end

      Rails.logger.info "[BrowseWebTool] Fetching URL: #{url}"

      service = WebBrowserService.new(timeout: 15)
      result = service.fetch(url, extract_text: extract_text)

      if result[:success]
        # Limit content length for the response
        content_preview = result[:content].to_s[0...3000]
        if result[:content].to_s.length > 3000
          content_preview += "\n\n[... #{result[:content].length - 3000} more characters ...]"
        end

        {
          success: true,
          message: "Successfully fetched '#{result[:title]}' from #{result[:url]}",
          data: {
            url: result[:url],
            title: result[:title],
            content: content_preview,
            content_type: result[:content_type],
            content_length: result[:content].length,
            truncated: result[:content].length > 3000
          }
        }
      else
        {
          success: false,
          message: "Failed to fetch URL: #{result[:error]}"
        }
      end
    rescue => e
      Rails.logger.error "[BrowseWebTool] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      {
        success: false,
        message: "An error occurred while browsing: #{e.message}"
      }
    end

    private

    def blocked_url?(url)
      blocked_patterns = [
        /localhost/i,
        /127\.\d+\.\d+\.\d+/,
        /192\.168\./,
        /10\.\d+\.\d+\.\d+/,
        /172\.(1[6-9]|2\d|3[01])\./,
        /file:/i,
        /ftp:/i,
        /\.internal$/i,
        /\.local$/i,
        /\.corp$/i
      ]

      blocked_patterns.any? { |pattern| url.match?(pattern) }
    end
  end
end
