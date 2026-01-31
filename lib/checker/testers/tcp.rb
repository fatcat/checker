# frozen_string_literal: true

require 'socket'
require 'timeout'

module Checker
  module Testers
    class Tcp < Base
      def run
        tcp_timeout = [config[:tcp_timeout] || 5, 10].min # Max 10 seconds

        result = measure_connection(tcp_timeout)

        if result[:success]
          record_result(
            reachable: true,
            latency_ms: result[:latency_ms].round(3)
          )

          {
            reachable: true,
            latency_ms: result[:latency_ms].round(3)
          }
        else
          record_result(
            reachable: false,
            error_message: result[:error] || "Connection failed"
          )

          { reachable: false, error: result[:error] }
        end
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

    end
  end
end
