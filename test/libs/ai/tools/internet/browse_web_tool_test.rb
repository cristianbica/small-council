# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internet
      class BrowseWebToolTest < ActiveSupport::TestCase
        setup do
          @tool = BrowseWebTool.new({})
        end

        test "read_only is true" do
          assert_equal true, BrowseWebTool.read_only
        end

        test "requires_approval is false" do
          assert_equal false, BrowseWebTool.requires_approval
        end

        test "execute returns successful fetch result" do
          mock_service = mock("web browser service")
          WebBrowserService.expects(:new).returns(mock_service)
          mock_service.expects(:fetch).with("https://example.com", extract_text: true).returns(
            { success: true, url: "https://example.com", title: "Example", content: "Example content" }
          )

          result = @tool.execute(url: "https://example.com")

          assert_equal true, result[:success]
          assert_equal "Example", result[:title]
        end

        test "execute returns error when url is missing" do
          WebBrowserService.expects(:new).never

          result = @tool.execute(url: nil)

          assert_equal false, result[:success]
          assert_match(/url is required/, result[:error])
        end

        test "execute returns error for invalid protocol" do
          WebBrowserService.expects(:new).never

          result = @tool.execute(url: "ftp://example.com")

          assert_equal false, result[:success]
          assert_match(/http\/https/, result[:error])
        end

        test "execute blocks localhost and private urls" do
          WebBrowserService.expects(:new).never

          localhost_result = @tool.execute(url: "http://localhost:3000/health")
          private_result = @tool.execute(url: "http://192.168.1.10/status")

          assert_equal false, localhost_result[:success]
          assert_match(/Blocked URL/, localhost_result[:error])

          assert_equal false, private_result[:success]
          assert_match(/Blocked URL/, private_result[:error])
        end
      end
    end
  end
end
