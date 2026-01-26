# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'timeout'

module Checker
  module Testers
    class Http < Base
      def run
        http_timeout = config[:http_timeout] || 10
        sample_count = config[:sample_count] || 3

        latencies = []
        statuses = []
        errors = []

        sample_count.times do
          result = measure_request(http_timeout)
          if result[:success]
            latencies << result[:latency_ms]
            statuses << result[:status]
          else
            errors << result[:error]
          end
        end

        if latencies.empty?
          record_result(
            reachable: false,
            error_message: errors.first || "Request failed"
          )
          return { reachable: false, error: errors.first }
        end

        avg_latency = latencies.sum / latencies.size
        jitter = calculate_ipdv(latencies)
        last_status = statuses.last
        # Consider reachable if we got any 2xx status code
        reachable = statuses.any? { |s| s >= 200 && s < 300 }

        record_result(
          reachable: reachable,
          latency_ms: avg_latency.round(3),
          jitter_ms: jitter.round(3),
          http_status: last_status,
          error_message: reachable ? nil : "HTTP status #{last_status} (expected 2xx)"
        )

        {
          reachable: reachable,
          latency_ms: avg_latency.round(3),
          jitter_ms: jitter.round(3),
          http_status: last_status,
          samples: latencies.size
        }
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
        scheme = port == 443 ? 'https' : 'http'
        host = address

        if port && ![80, 443].include?(port)
          "#{scheme}://#{host}:#{port}"
        else
          "#{scheme}://#{host}"
        end
      end

      def calculate_ipdv(latencies)
        return 0.0 if latencies.size < 2

        delay_variations = []
        (1...latencies.size).each do |i|
          variation = (latencies[i] - latencies[i - 1]).abs
          delay_variations << variation
        end

        delay_variations.sum / delay_variations.size
      end
    end
  end
end
