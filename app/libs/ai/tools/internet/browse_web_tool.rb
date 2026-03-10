# frozen_string_literal: true

require "ipaddr"
require "uri"

module AI
  module Tools
    module Internet
      class BrowseWebTool < AbstractTool
        self.requires_approval = false
        self.read_only = true

        description "Fetch and summarize readable content from a public web URL"

        params do
          string :url, description: "Public URL to browse (http/https only)", required: true
          boolean :extract_text, description: "Extract readable text from HTML", required: false
        end

        def execute(url:, extract_text: true)
          return { success: false, error: "url is required" } if url.blank?

          normalized_url = normalize_and_validate_url(url)
          return { success: false, error: "Only http/https URLs are allowed" } unless normalized_url
          return { success: false, error: "Blocked URL: localhost/private/internal addresses are not allowed" } if blocked_target?(normalized_url)

          WebBrowserService.new.fetch(normalized_url, extract_text: extract_text)
        rescue WebBrowserService::InvalidURLError => e
          { success: false, error: e.message }
        end

        private

        def normalize_and_validate_url(url)
          candidate = url.to_s.strip
          return nil if candidate.blank?
          return nil if candidate.match?(/\A[A-Za-z][A-Za-z0-9+.-]*:\/\//) && !candidate.match?(/\Ahttps?:\/\//i)

          candidate = "https://#{candidate}" unless candidate.match?(/\Ahttps?:\/\//i)
          uri = URI.parse(candidate)

          return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          return nil if uri.host.blank?

          uri.to_s
        rescue URI::InvalidURIError
          nil
        end

        def blocked_target?(url)
          uri = URI.parse(url)
          host = uri.host.to_s.downcase

          blocked_hostname?(host) || blocked_ip?(host)
        rescue URI::InvalidURIError
          true
        end

        def blocked_hostname?(host)
          return true if host == "localhost" || host.end_with?(".localhost")

          host.end_with?(".local", ".internal")
        end

        def blocked_ip?(host)
          ip = IPAddr.new(host)
          blocked_ip_ranges.any? { |range| range.include?(ip) }
        rescue IPAddr::InvalidAddressError
          false
        end

        def blocked_ip_ranges
          @blocked_ip_ranges ||= [
            IPAddr.new("0.0.0.0/8"),
            IPAddr.new("10.0.0.0/8"),
            IPAddr.new("127.0.0.0/8"),
            IPAddr.new("169.254.0.0/16"),
            IPAddr.new("172.16.0.0/12"),
            IPAddr.new("192.168.0.0/16"),
            IPAddr.new("::/128"),
            IPAddr.new("::1/128"),
            IPAddr.new("fc00::/7"),
            IPAddr.new("fe80::/10")
          ]
        end
      end
    end
  end
end
