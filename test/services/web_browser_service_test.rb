require "test_helper"

class WebBrowserServiceTest < ActiveSupport::TestCase
  setup do
    @service = WebBrowserService.new
  end

  # ============================================================================
  # URL Normalization Tests
  # ============================================================================

  test "normalize_url adds https:// when no scheme provided" do
    result = @service.send(:normalize_url, "example.com")
    assert_equal "https://example.com", result
  end

  test "normalize_url preserves http:// scheme" do
    result = @service.send(:normalize_url, "http://example.com")
    assert_equal "http://example.com", result
  end

  test "normalize_url preserves https:// scheme" do
    result = @service.send(:normalize_url, "https://example.com")
    assert_equal "https://example.com", result
  end

  test "normalize_url returns nil for blank url" do
    result = @service.send(:normalize_url, "")
    assert_nil result
  end

  test "normalize_url returns nil for nil url" do
    result = @service.send(:normalize_url, nil)
    assert_nil result
  end

  test "normalize_url returns nil for invalid URI" do
    result = @service.send(:normalize_url, "not a valid url ::: ")
    assert_nil result
  end

  test "normalize_url only preserves explicit http or https schemes" do
    result = @service.send(:normalize_url, "ftp://example.com/file")
    assert_equal "https://ftp//example.com/file", result
  end

  test "normalize_url handles URLs with paths" do
    result = @service.send(:normalize_url, "example.com/path/to/page")
    assert_equal "https://example.com/path/to/page", result
  end

  test "normalize_url handles URLs with query strings" do
    result = @service.send(:normalize_url, "example.com?foo=bar")
    assert_equal "https://example.com?foo=bar", result
  end

  # ============================================================================
  # HTML Processing Tests
  # ============================================================================

  test "process_html extracts title with Nokogiri" do
    html = <<~HTML
      <html>
        <head><title>Test Page Title</title></head>
        <body><p>Content here</p></body>
      </html>
    HTML

    result = @service.send(:process_html, html, "https://example.com", extract_text: true)

    assert_equal "Test Page Title", result[:title]
    assert_equal "https://example.com", result[:url]
    assert result[:success]
  end

  test "process_html extracts content from main element" do
    html = <<~HTML
      <html>
        <head><title>Test</title></head>
        <body>
          <nav>Navigation</nav>
          <main>
            <h1>Main Content</h1>
            <p>This is the main content.</p>
          </main>
          <footer>Footer</footer>
        </body>
      </html>
    HTML

    result = @service.send(:process_html, html, "https://example.com", extract_text: true)

    assert_includes result[:content], "Main Content"
    assert_includes result[:content], "This is the main content"
    # Should not include nav or footer
    refute_includes result[:content], "Navigation"
    refute_includes result[:content], "Footer"
  end

  test "process_html falls back to body when no main element" do
    html = <<~HTML
      <html>
        <head><title>Test</title></head>
        <body>
          <p>Body content here.</p>
        </body>
      </html>
    HTML

    result = @service.send(:process_html, html, "https://example.com", extract_text: true)

    assert_includes result[:content], "Body content here"
  end

  test "process_html removes script and style elements" do
    html = <<~HTML
      <html>
        <head><title>Test</title></head>
        <body>
          <script>alert('xss')</script>
          <style>.hidden { display: none; }</style>
          <p>Visible content.</p>
        </body>
      </html>
    HTML

    result = @service.send(:process_html, html, "https://example.com", extract_text: true)

    refute_includes result[:content], "alert"
    refute_includes result[:content], "display: none"
    assert_includes result[:content], "Visible content"
  end

  test "process_html truncates content when too long" do
    long_content = "a" * 60000
    html = <<~HTML
      <html>
        <head><title>Test</title></head>
        <body><p>#{long_content}</p></body>
      </html>
    HTML

    result = @service.send(:process_html, html, "https://example.com", extract_text: true)

    assert result[:content].length <= WebBrowserService::MAX_CONTENT_LENGTH + 50 # Allow for truncation message
    assert_includes result[:content], "[Content truncated...]"
  end

  test "process_html returns raw html when extract_text is false" do
    html = "<html><body>Raw content</body></html>"

    result = @service.send(:process_html, html, "https://example.com", extract_text: false)

    assert_equal html, result[:content]
    assert_equal "Unknown", result[:title]
  end

  test "process_html handles parsing errors gracefully" do
    # Invalid HTML that might cause parsing issues
    html = "<html><body>Content without proper closing"

    result = @service.send(:process_html, html, "https://example.com", extract_text: true)

    assert result[:success]
    assert_equal "https://example.com", result[:url]
  end

  # ============================================================================
  # Regex-based Extraction Tests (fallback)
  # ============================================================================

  test "extract_with_regex extracts title" do
    html = "<html><head><title>Regex Test Title</title></head><body>Content</body></html>"

    result = @service.send(:extract_with_regex, html, "https://example.com")

    assert_equal "Regex Test Title", result[:title]
  end

  test "extract_with_regex handles no title tag" do
    html = "<html><body>Content without title</body></html>"

    result = @service.send(:extract_with_regex, html, "https://example.com")

    assert_equal "No Title", result[:title]
  end

  test "extract_with_regex decodes HTML entities" do
    html = "<html><body>&lt;div&gt; &amp; &quot;quotes&quot;</body></html>"

    result = @service.send(:extract_with_regex, html, "https://example.com")

    assert_includes result[:content], "<div>"
    assert_includes result[:content], "&"
    assert_includes result[:content], '"quotes"'
  end

  test "extract_with_regex removes script tags" do
    html = "<html><body><script>var x = 1;</script><p>Clean content</p></body></html>"

    result = @service.send(:extract_with_regex, html, "https://example.com")

    refute_includes result[:content], "var x"
    assert_includes result[:content], "Clean content"
  end

  test "extract_with_regex truncates very long content" do
    html = "<html><body>#{'x' * 70000}</body></html>"

    result = @service.send(:extract_with_regex, html, "https://example.com")

    assert_includes result[:content], "[Content truncated...]"
    assert result[:content].length <= WebBrowserService::MAX_CONTENT_LENGTH + 50
  end

  # ============================================================================
  # Connection Building Tests
  # ============================================================================

  test "build_connection creates Faraday connection with proper config" do
    service = WebBrowserService.new(timeout: 15)
    conn = service.send(:build_connection)

    assert_instance_of Faraday::Connection, conn
    assert_equal 15, conn.options.timeout
    assert_equal 15, conn.options.open_timeout
  end

  test "build_connection sets browser-like User-Agent" do
    conn = @service.send(:build_connection)

    assert_includes conn.headers["User-Agent"], "Mozilla/5.0"
    assert_includes conn.headers["User-Agent"], "SmallCouncilBot"
  end

  # ============================================================================
  # Fetch Error Handling Tests
  # ============================================================================

  test "fetch raises InvalidURLError for invalid URL" do
    error = assert_raises(WebBrowserService::InvalidURLError) do
      @service.fetch("not a valid url ::: ")
    end
    assert_match(/Invalid URL/, error.message)
  end

  test "fetch handles Faraday connection errors" do
    service = WebBrowserService.new
    mock_conn = mock("connection")
    mock_conn.expects(:get).raises(Faraday::ConnectionFailed.new("Connection refused"))
    service.instance_variable_set(:@connection, mock_conn)

    result = service.fetch("https://example.com")

    assert_equal false, result[:success]
    assert_match(/Connection failed/, result[:error])
  end

  test "fetch handles Faraday timeout errors" do
    service = WebBrowserService.new
    mock_conn = mock("connection")
    mock_conn.expects(:get).raises(Faraday::TimeoutError.new("Request timed out"))
    service.instance_variable_set(:@connection, mock_conn)

    result = service.fetch("https://example.com")

    assert_equal false, result[:success]
    assert_match(/Request timed out/, result[:error])
  end

  test "fetch handles general errors gracefully" do
    service = WebBrowserService.new
    mock_conn = mock("connection")
    mock_conn.expects(:get).raises(StandardError.new("Unexpected error"))
    service.instance_variable_set(:@connection, mock_conn)

    result = service.fetch("https://example.com")

    assert_equal false, result[:success]
    assert_match(/Error/, result[:error])
  end

  test "fetch handles non-success HTTP responses" do
    service = WebBrowserService.new
    mock_response = Struct.new(:status, :success?, :reason_phrase, :headers, :body).new(
      404, false, "Not Found", {}, "Not found"
    )
    mock_conn = mock("connection")
    mock_conn.expects(:get).returns(mock_response)
    service.instance_variable_set(:@connection, mock_conn)

    result = service.fetch("https://example.com")

    assert_equal false, result[:success]
    assert_match(/HTTP 404/, result[:error])
  end

  test "fetch handles text/plain content type" do
    service = WebBrowserService.new
    mock_response = Struct.new(:status, :success?, :reason_phrase, :headers, :body).new(
      200, true, "OK", { "content-type" => "text/plain" }, "Plain text content"
    )
    mock_conn = mock("connection")
    mock_conn.expects(:get).returns(mock_response)
    service.instance_variable_set(:@connection, mock_conn)

    result = service.fetch("https://example.com/file.txt")

    assert_equal true, result[:success]
    assert_equal "Text Document", result[:title]
    assert_equal "Plain text content", result[:content]
  end

  test "fetch handles binary content type" do
    service = WebBrowserService.new
    mock_response = Struct.new(:status, :success?, :reason_phrase, :headers, :body).new(
      200, true, "OK", { "content-type" => "application/pdf" }, "binary data"
    )
    mock_conn = mock("connection")
    mock_conn.expects(:get).returns(mock_response)
    service.instance_variable_set(:@connection, mock_conn)

    result = service.fetch("https://example.com/file.pdf")

    assert_equal true, result[:success]
    assert_equal "Binary Content", result[:title]
    assert_match(/Content type: application\/pdf/, result[:content])
  end

  test "fetch handles HTML content type" do
    html_body = "<html><head><title>Test Page</title></head><body><p>Content</p></body></html>"
    service = WebBrowserService.new
    mock_response = Struct.new(:status, :success?, :reason_phrase, :headers, :body).new(
      200, true, "OK", { "content-type" => "text/html" }, html_body
    )
    mock_conn = mock("connection")
    mock_conn.expects(:get).returns(mock_response)
    service.instance_variable_set(:@connection, mock_conn)

    result = service.fetch("https://example.com")

    assert_equal true, result[:success]
    assert_equal "Test Page", result[:title]
    assert_includes result[:content], "Content"
  end

  test "fetch handles no content-type header" do
    html_body = "<html><head><title>Test</title></head><body>Content</body></html>"
    service = WebBrowserService.new
    mock_response = Struct.new(:status, :success?, :reason_phrase, :headers, :body).new(
      200, true, "OK", {}, html_body
    )
    mock_conn = mock("connection")
    mock_conn.expects(:get).returns(mock_response)
    service.instance_variable_set(:@connection, mock_conn)

    result = service.fetch("https://example.com")

    assert_equal true, result[:success]
    assert_equal "Test", result[:title]
  end

  # ============================================================================
  # Integration-style Tests
  # ============================================================================

  test "successful fetch returns complete result hash" do
    html_body = <<~HTML
      <html>
        <head><title>Integration Test</title></head>
        <body>
          <main>
            <h1>Main Heading</h1>
            <p>First paragraph.</p>
            <p>Second paragraph.</p>
          </main>
        </body>
      </html>
    HTML

    service = WebBrowserService.new
    mock_response = Struct.new(:status, :success?, :reason_phrase, :headers, :body).new(
      200, true, "OK", { "content-type" => "text/html; charset=utf-8" }, html_body
    )
    mock_conn = mock("connection")
    mock_conn.expects(:get).returns(mock_response)
    service.instance_variable_set(:@connection, mock_conn)

    result = service.fetch("https://example.com/page")

    assert result[:success]
    assert_equal "https://example.com/page", result[:url]
    assert_equal "Integration Test", result[:title]
    assert_includes result[:content], "Main Heading"
    assert_includes result[:content], "First paragraph"
    assert_includes result[:content], "Second paragraph"
    assert_equal "text/html", result[:content_type]
  end

  test "fetch with extract_text false returns raw HTML" do
    html_body = "<html><body>Raw HTML content</body></html>"
    service = WebBrowserService.new
    mock_response = Struct.new(:status, :success?, :reason_phrase, :headers, :body).new(
      200, true, "OK", { "content-type" => "text/html" }, html_body
    )
    mock_conn = mock("connection")
    mock_conn.expects(:get).returns(mock_response)
    service.instance_variable_set(:@connection, mock_conn)

    result = service.fetch("https://example.com", extract_text: false)

    assert_equal html_body, result[:content]
  end
end
