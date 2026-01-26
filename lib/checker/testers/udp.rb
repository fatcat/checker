# frozen_string_literal: true

require 'socket'
require 'timeout'

module Checker
  module Testers
    class Udp < Base
      # UDP testing is inherently different from TCP:
      # - UDP is connectionless, so we can't simply "connect"
      # - No response doesn't necessarily mean failure
      # - We send a probe packet and measure if we get ICMP unreachable
      #
      # Strategy:
      # - Send an empty UDP packet
      # - If we get ICMP "port unreachable" -> host is up but port closed
      # - If we get no response -> port may be open (or filtered)
      # - For latency, we do a combined ping + UDP probe approach

      def run
        udp_timeout = config[:tcp_timeout] || 5  # Reuse tcp_timeout setting
        sample_count = config[:sample_count] || 3

        latencies = []
        errors = []

        sample_count.times do
          result = probe_udp(udp_timeout)
          if result[:success]
            latencies << result[:latency_ms] if result[:latency_ms]
          else
            errors << result[:error]
          end
        end

        # For UDP, "no response" often means open, so we're more lenient
        # If we didn't get explicit errors (like host unreachable), consider it reachable
        reachable = errors.count { |e| e.include?("unreachable") } < sample_count

        if reachable && latencies.any?
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
        elsif reachable
          # Reachable but no latency data (UDP didn't respond, which is normal)
          record_result(
            reachable: true,
            latency_ms: nil,
            jitter_ms: nil
          )

          { reachable: true, latency_ms: nil, note: "No UDP response (normal for many services)" }
        else
          record_result(
            reachable: false,
            error_message: errors.first || "Host unreachable"
          )

          { reachable: false, error: errors.first }
        end
      end

      private

      def probe_udp(timeout_seconds)
        start_time = Time.now

        socket = UDPSocket.new
        socket.connect(address, port)

        # Send an empty probe packet
        socket.send("", 0)

        # Try to receive a response (most UDP services won't respond to empty packets)
        begin
          Timeout.timeout(timeout_seconds) do
            socket.recv(1024)
            latency_ms = (Time.now - start_time) * 1000
            { success: true, latency_ms: latency_ms }
          end
        rescue Timeout::Error
          # No response is normal for UDP - we'll use the send time as a basic check
          latency_ms = (Time.now - start_time) * 1000
          { success: true, latency_ms: nil }
        end
      rescue Errno::ECONNREFUSED
        # ICMP port unreachable - host is up but port is closed
        latency_ms = (Time.now - start_time) * 1000
        { success: true, latency_ms: latency_ms, note: "Port closed but host reachable" }
      rescue Errno::ENETUNREACH
        { success: false, error: "Network unreachable" }
      rescue Errno::EHOSTUNREACH
        { success: false, error: "Host unreachable" }
      rescue StandardError => e
        { success: false, error: e.message }
      ensure
        socket&.close
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
