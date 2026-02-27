# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module External
      class BrowseWebToolTest < ActiveSupport::TestCase
        setup do
          @tool = BrowseWebTool.new
        end

        test "name returns browse_web" do
          assert_equal "browse_web", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("web")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:url)
          assert params[:properties].key?(:extract_text)
          assert_includes params[:required], :url
        end

        test "execute returns error without url" do
          result = @tool.execute({}, {})
          assert_not result[:success]
          assert_equal "URL is required", result[:error]
        end

        test "execute returns error for blank url" do
          result = @tool.execute({ url: "" }, {})
          assert_not result[:success]
          assert_equal "URL is required", result[:error]
        end

        test "execute returns error for invalid url format" do
          result = @tool.execute({ url: "example.com" }, {})
          assert_not result[:success]
          assert_match(/Invalid URL format/, result[:error])
        end

        test "execute returns error for ftp url" do
          result = @tool.execute({ url: "ftp://example.com/file.txt" }, {})
          assert_not result[:success]
          assert_match(/blocked for security/, result[:error])
        end

        test "execute returns error for localhost" do
          result = @tool.execute({ url: "http://localhost:3000" }, {})
          assert_not result[:success]
          assert_match(/blocked for security/, result[:error])
        end

        test "execute returns error for 127.0.0.1" do
          result = @tool.execute({ url: "http://127.0.0.1:3000" }, {})
          assert_not result[:success]
          assert_match(/blocked for security/, result[:error])
        end

        test "execute returns error for private ip ranges" do
          result = @tool.execute({ url: "http://192.168.1.1" }, {})
          assert_not result[:success]
          assert_match(/blocked for security/, result[:error])

          result = @tool.execute({ url: "http://10.0.0.1" }, {})
          assert_not result[:success]
          assert_match(/blocked for security/, result[:error])

          result = @tool.execute({ url: "http://172.16.0.1" }, {})
          assert_not result[:success]
          assert_match(/blocked for security/, result[:error])
        end

        test "execute returns error for file protocol" do
          result = @tool.execute({ url: "file:///etc/passwd" }, {})
          assert_not result[:success]
          assert_match(/blocked for security/, result[:error])
        end

        test "execute returns error for .local domains" do
          result = @tool.execute({ url: "http://myserver.local" }, {})
          assert_not result[:success]
          assert_match(/blocked for security/, result[:error])
        end

        test "execute accepts https urls" do
          # Mock the WebBrowserService to avoid actual HTTP calls
          mock_result = {
            success: true,
            url: "https://example.com",
            title: "Example Domain",
            content: "This is example content.",
            content_type: "text/html"
          }

          WebBrowserService.any_instance.stubs(:fetch).returns(mock_result)

          result = @tool.execute({ url: "https://example.com" }, {})

          assert result[:success]
          assert_equal "https://example.com", result[:url]
          assert_equal "Example Domain", result[:title]
        end

        test "execute accepts http urls" do
          mock_result = {
            success: true,
            url: "http://example.com",
            title: "Example Domain",
            content: "This is example content.",
            content_type: "text/html"
          }

          WebBrowserService.any_instance.stubs(:fetch).returns(mock_result)

          result = @tool.execute({ url: "http://example.com" }, {})

          assert result[:success]
        end

        test "execute truncates long content" do
          long_content = "a" * 10000
          mock_result = {
            success: true,
            url: "https://example.com",
            title: "Long Content",
            content: long_content,
            content_type: "text/html"
          }

          WebBrowserService.any_instance.stubs(:fetch).returns(mock_result)

          result = @tool.execute({ url: "https://example.com" }, {})

          assert result[:success]
          assert result[:truncated]
          assert result[:content].length <= 5100  # 5000 + truncation message
        end

        test "execute handles browser service failure" do
          mock_result = {
            success: false,
            url: "https://example.com",
            error: "Connection timeout"
          }

          WebBrowserService.any_instance.stubs(:fetch).returns(mock_result)

          result = @tool.execute({ url: "https://example.com" }, {})

          assert_not result[:success]
          assert_match(/Failed to fetch URL/, result[:error])
          assert result[:error].include?("Connection timeout")
        end

        test "execute handles exceptions gracefully" do
          WebBrowserService.any_instance.stubs(:fetch).raises(StandardError, "Network error")

          result = @tool.execute({ url: "https://example.com" }, {})

          assert_not result[:success]
          assert_match(/error occurred/, result[:error])
        end

        test "execute defaults extract_text to true" do
          mock_result = {
            success: true,
            url: "https://example.com",
            title: "Example",
            content: "Content",
            content_type: "text/html"
          }

          WebBrowserService.any_instance.expects(:fetch).with("https://example.com", extract_text: true).returns(mock_result)

          @tool.execute({ url: "https://example.com" }, {})
        end

        test "execute respects extract_text false" do
          mock_result = {
            success: true,
            url: "https://example.com",
            title: "Example",
            content: "Content",
            content_type: "text/html"
          }

          WebBrowserService.any_instance.stubs(:fetch).returns(mock_result)

          result = @tool.execute({ url: "https://example.com", extract_text: false }, {})
          assert result[:success]
        end

        test "execute includes content metadata" do
          mock_result = {
            success: true,
            url: "https://example.com",
            title: "Example Page",
            content: "This is the page content.",
            content_type: "text/html"
          }

          WebBrowserService.any_instance.stubs(:fetch).returns(mock_result)

          result = @tool.execute({ url: "https://example.com" }, {})

          assert result[:success]
          assert_equal "text/html", result[:content_type]
          assert result[:content_length] > 0
        end
      end
    end
  end
end
