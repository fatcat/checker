# frozen_string_literal: true

require 'open3'

module Checker
  module Testers
    class Jitter < Base
      def run
        ping_count = 5  # Always 5 pings for jitter
        ping_timeout = [config[:ping_timeout] || 5, 10].min

        latencies = execute_ping(ping_count, ping_timeout)

        if latencies.empty?
          record_result(
            reachable: false,
            error_message: "Host unreachable (jitter test)"
          )
          return { reachable: false, error: "Host unreachable (jitter test)" }
        end

        # Need at least 2 pings to calculate jitter
        if latencies.size < 2
          record_result(
            reachable: false,
            error_message: "Insufficient ping responses for jitter calculation"
          )
          return {
            reachable: false,
            error: "Insufficient ping responses for jitter calculation"
          }
        end

        avg_latency = latencies.sum / latencies.size
        jitter = calculate_ipdv(latencies)

        record_result(
          reachable: true,
          latency_ms: avg_latency.round(3),  # Store avg latency as byproduct
          jitter_ms: jitter.round(3)
        )

        {
          reachable: true,
          latency_ms: avg_latency.round(3),
          jitter_ms: jitter.round(3),
          samples: latencies.size
        }
      end

      private

      def execute_ping(count, timeout)
        # Same as ping tester: 5 pings with 0.2s interval
        cmd = "ping -c #{count} -W #{timeout} -i 0.2 #{address} 2>&1"
        stdout, status = Open3.capture2(cmd)
        return [] unless status.success?

        # Parse ping output to extract RTT values
        latencies = stdout.scan(/time[=<]([\d.]+)\s*ms/).flatten.map(&:to_f)
        latencies
      end

      # Calculate Inter-Packet Delay Variation (IPDV) - RFC 3393
      # IPDV measures the difference in delay between consecutive packets
      def calculate_ipdv(latencies)
        return 0.0 if latencies.size < 2

        # Calculate delay differences between consecutive packets
        delay_variations = []
        (1...latencies.size).each do |i|
          variation = (latencies[i] - latencies[i - 1]).abs
          delay_variations << variation
        end

        # Return mean absolute IPDV
        delay_variations.sum / delay_variations.size
      end
    end
  end
end
