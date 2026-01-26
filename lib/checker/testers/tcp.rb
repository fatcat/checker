# frozen_string_literal: true

require 'socket'
require 'timeout'

module Checker
  module Testers
    class Tcp < Base
      def run
        tcp_timeout = config[:tcp_timeout] || 5
        sample_count = config[:sample_count] || 3

        latencies = []
        errors = []

        sample_count.times do
          result = measure_connection(tcp_timeout)
          if result[:success]
            latencies << result[:latency_ms]
          else
            errors << result[:error]
          end
        end

        if latencies.empty?
          record_result(
            reachable: false,
            error_message: errors.first || "Connection failed"
          )
          return { reachable: false, error: errors.first }
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

      def measure_connection(timeout_seconds)
        start_time = Time.now

        Timeout.timeout(timeout_seconds) do
          socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
          begin
            sockaddr = Socket.sockaddr_in(port, address)
            socket.connect_nonblock(sockaddr)
          rescue IO::WaitWritable
            IO.select(nil, [socket], nil, timeout_seconds)
            begin
              socket.connect_nonblock(sockaddr)
            rescue Errno::EISCONN
              # Already connected - this is success
            end
          end
          socket.close

          latency_ms = (Time.now - start_time) * 1000
          { success: true, latency_ms: latency_ms }
        end
      rescue Timeout::Error
        { success: false, error: "Connection timed out" }
      rescue Errno::ECONNREFUSED
        { success: false, error: "Connection refused" }
      rescue Errno::ENETUNREACH
        { success: false, error: "Network unreachable" }
      rescue Errno::EHOSTUNREACH
        { success: false, error: "Host unreachable" }
      rescue StandardError => e
        { success: false, error: e.message }
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
