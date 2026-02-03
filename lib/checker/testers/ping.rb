# frozen_string_literal: true

require 'open3'
require 'shellwords'

module Checker
  module Testers
    class Ping < Base
      def run
        ping_count = 1  # Single ping for latency only
        ping_timeout = [config[:ping_timeout] || 5, 10].min # Max 10 seconds

        latencies = execute_ping(ping_count, ping_timeout)

        if latencies.empty?
          record_result(
            reachable: false,
            error_message: "Host unreachable"
          )
          return { reachable: false, error: "Host unreachable" }
        end

        latency = latencies.first

        record_result(
          reachable: true,
          latency_ms: latency.round(3)
        )

        {
          reachable: true,
          latency_ms: latency.round(3),
          samples: 1
        }
      end

      private

      def execute_ping(count, timeout)
        # Use system ping command (works without root, unlike raw ICMP)
        # -c = count, -W = timeout per ping (Linux), -i = interval
        # Use Shellwords.shellescape to prevent command injection
        safe_address = Shellwords.shellescape(address)
        cmd = "ping -c #{count} -W #{timeout} -i 0.2 #{safe_address} 2>&1"

        stdout, status = Open3.capture2(cmd)

        return [] unless status.success?

        # Parse ping output to extract RTT values
        # Format: "64 bytes from x.x.x.x: icmp_seq=1 ttl=64 time=1.23 ms"
        latencies = stdout.scan(/time[=<]([\d.]+)\s*ms/).flatten.map(&:to_f)

        latencies
      end
    end
  end
end
