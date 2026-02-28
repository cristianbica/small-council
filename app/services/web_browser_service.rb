# Service to fetch and process web content
# Handles HTTP requests, redirects, and content extraction
class WebBrowserService
  class Error < StandardError; end
  class FetchError < Error; end
  class TimeoutError < Error; end
  class InvalidURLError < Error; end

  DEFAULT_TIMEOUT = 10
  MAX_REDIRECTS = 3
  MAX_CONTENT_LENGTH = 50000 # 50KB max to avoid huge pages

  def initialize(timeout: DEFAULT_TIMEOUT)
    @timeout = timeout
    @connection = build_connection
  end

  # Fetch content from a URL
  # @param url [String] The URL to fetch
  # @param extract_text [Boolean] Whether to extract readable text (default: true)
  # @return [Hash] Result with :success, :url, :title, :content, :error
  def fetch(url, extract_text: true)
    normalized_url = normalize_url(url)
    raise InvalidURLError, "Invalid URL: #{url}" unless normalized_url

    response = @connection.get(normalized_url)

    if response.success?
      content_type = response.headers["content-type"] || "text/html"

      if content_type.include?("text/html")
        process_html(response.body, normalized_url, extract_text: extract_text)
      elsif content_type.include?("text/plain")
        {
          success: true,
          url: normalized_url,
          title: "Text Document",
          content: response.body.to_s[0...MAX_CONTENT_LENGTH],
          content_type: content_type
        }
      else
        {
          success: true,
          url: normalized_url,
          title: "Binary Content",
          content: "[Content type: #{content_type} - cannot display]",
          content_type: content_type
        }
      end
    else
      {
        success: false,
        url: normalized_url,
        error: "HTTP #{response.status}: #{response.reason_phrase}"
      }
    end
  rescue Faraday::ConnectionFailed => e
    { success: false, url: url, error: "Connection failed: #{e.message}" }
  rescue Faraday::TimeoutError => e
    { success: false, url: url, error: "Request timed out after #{@timeout} seconds" }
  rescue InvalidURLError
    raise  # Re-raise InvalidURLError so callers can handle it
  rescue => e
    Rails.logger.error "[WebBrowserService] Error fetching #{url}: #{e.message}"
    { success: false, url: url, error: "Error: #{e.message}" }
  end

  private

  def build_connection
    Faraday.new do |conn|
      conn.options.timeout = @timeout
      conn.options.open_timeout = @timeout

      # Follow redirects
      conn.response :follow_redirects, limit: MAX_REDIRECTS

      # Set a browser-like User-Agent
      conn.headers["User-Agent"] = "Mozilla/5.0 (compatible; SmallCouncilBot/1.0; +https://github.com/small-council)"

      # Only follow safe redirects
      conn.adapter Faraday.default_adapter
    end
  end

  def normalize_url(url)
    return nil if url.blank?

    # Add https:// if no scheme provided
    url = "https://#{url}" unless url.match?(/\Ahttps?:\/\//i)

    # Validate URL format
    uri = URI.parse(url)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def process_html(html, url, extract_text: true)
    return { success: true, url: url, title: "Unknown", content: html } unless extract_text

    # Use Nokogiri if available, otherwise simple regex extraction
    if defined?(Nokogiri)
      extract_with_nokogiri(html, url)
    else
      extract_with_regex(html, url)
    end
  rescue => e
    Rails.logger.error "[WebBrowserService] Error processing HTML: #{e.message}"
    { success: true, url: url, title: "Error extracting", content: html[0...MAX_CONTENT_LENGTH] }
  end

  def extract_with_nokogiri(html, url)
    doc = Nokogiri::HTML(html)

    # Extract title
    title = doc.at_css("title")&.text&.strip || "No Title"

    # Remove script and style elements
    doc.css("script, style, nav, header, footer, aside").each(&:remove)

    # Try to find main content
    content_element = doc.at_css('main, article, [role="main"], .content, #content')
    content = if content_element
      content_element.text
    else
      doc.at_css("body")&.text || doc.text
    end

    # Clean up whitespace
    content = content.gsub(/\s+/, " ").strip

    # Truncate if too long
    content = content[0...MAX_CONTENT_LENGTH] + "\n\n[Content truncated...]" if content.length > MAX_CONTENT_LENGTH

    {
      success: true,
      url: url,
      title: title,
      content: content,
      content_type: "text/html"
    }
  end

  def extract_with_regex(html, url)
    # Simple fallback extraction without Nokogiri
    title = html.match(/<title[^>]*>([^<]*)<\/title>/i)&.captures&.first&.strip || "No Title"

    # Remove script and style tags with content
    cleaned = html.gsub(/<(script|style)[^>]*>.*?<\/\1>/mi, " ")

    # Remove all HTML tags
    text = cleaned.gsub(/<[^>]+>/, " ")

    # Decode common HTML entities
    text = text.gsub(/&lt;/, "<").gsub(/&gt;/, ">").gsub(/&amp;/, "&").gsub(/&quot;/, '"')

    # Clean up whitespace
    text = text.gsub(/\s+/, " ").strip

    # Truncate
    text = text[0...MAX_CONTENT_LENGTH] + "\n\n[Content truncated...]" if text.length > MAX_CONTENT_LENGTH

    {
      success: true,
      url: url,
      title: title,
      content: text,
      content_type: "text/html"
    }
  end
end
