# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'timeout'

module Checker
  module Testers
    class Http < Base
      def run
        http_timeout = [config[:http_timeout] || 10, 10].min # Max 10 seconds

        result = measure_request(http_timeout)

        if result[:success]
          # Consider reachable if we got a 2xx status code
          reachable = result[:status] >= 200 && result[:status] < 300

          record_result(
            reachable: reachable,
            latency_ms: result[:latency_ms].round(3),
            http_status: result[:status],
            error_message: reachable ? nil : "HTTP status #{result[:status]} (expected 2xx)"
          )

          {
            reachable: reachable,
            latency_ms: result[:latency_ms].round(3),
            http_status: result[:status]
          }
        else
          record_result(
            reachable: false,
            error_message: result[:error] || "Request failed"
          )

          { reachable: false, error: result[:error] }
        end
      end

      private

      def measure_request(timeout_seconds)
        url = build_url
        start_time = Time.now

        conn = Faraday.new(url: url) do |f|
          f.options.timeout = timeout_seconds
          f.options.open_timeout = timeout_seconds
          # Follow redirects (up to 5 hops) to reach final destination
          f.response :follow_redirects, limit: 5
          f.adapter Faraday.default_adapter
        end

        response = conn.get
        latency_ms = (Time.now - start_time) * 1000

        {
          success: true,
          latency_ms: latency_ms,
          status: response.status
        }
      rescue Faraday::TimeoutError
        { success: false, error: "Request timed out" }
      rescue Faraday::ConnectionFailed => e
        { success: false, error: "Connection failed: #{e.message}" }
      rescue Faraday::SSLError => e
        { success: false, error: "SSL error: #{e.message}" }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def build_url
        scheme = test.http_scheme || (port == 443 ? 'https' : 'http')
        host_address = address

        if port && ![80, 443].include?(port)
          "#{scheme}://#{host_address}:#{port}"
        else
          "#{scheme}://#{host_address}"
        end
      end

    end
  end
end
