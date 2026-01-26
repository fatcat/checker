# frozen_string_literal: true

require 'open3'

module Checker
  module Testers
    class Ping < Base
      def run
        ping_count = config[:ping_count] || 5
        ping_timeout = config[:ping_timeout] || 5

        latencies = execute_ping(ping_count, ping_timeout)

        if latencies.empty?
          record_result(
            reachable: false,
            error_message: "Host unreachable"
          )
          return { reachable: false, error: "Host unreachable" }
        end

        avg_latency = latencies.sum / latencies.size
        jitter = calculate_ipdv(latencies)

        record_result(
          reachable: true,
          latency_ms: avg_latency.round(3),
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
        # Use system ping command (works without root, unlike raw ICMP)
        # -c = count, -W = timeout per ping (Linux), -i = interval
        cmd = "ping -c #{count} -W #{timeout} -i 0.2 #{address} 2>&1"

        stdout, status = Open3.capture2(cmd)

        return [] unless status.success?

        # Parse ping output to extract RTT values
        # Format: "64 bytes from x.x.x.x: icmp_seq=1 ttl=64 time=1.23 ms"
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
