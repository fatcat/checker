# frozen_string_literal: true

require 'resolv'
require 'timeout'

module Checker
  module Testers
    class Dns < Base
      def run
        query_hostname = test.dns_query_hostname
        dns_server = address
        dns_timeout = [config[:dns_timeout] || 5, 10].min # Max 10 seconds

        unless query_hostname && !query_hostname.empty?
          result = { reachable: false, error_message: 'No query hostname configured' }
          record_result(reachable: false, error_message: result[:error_message])
          return result
        end

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        resolved = false
        resolved_addresses = []
        error_msg = nil

        # Use Thread-based timeout for more reliable interruption
        query_thread = Thread.new do
          begin
            # Create resolver with custom nameserver
            resolver = Resolv::DNS.new(nameserver: [dns_server])

            addresses = resolver.getaddresses(query_hostname)

            if addresses.any?
              { success: true, addresses: addresses.map(&:to_s) }
            else
              { success: false, error: "No addresses returned for #{query_hostname}" }
            end
          rescue Resolv::ResolvError => e
            { success: false, error: "DNS resolution failed: #{e.message}" }
          rescue StandardError => e
            { success: false, error: "DNS error: #{e.message}" }
          ensure
            resolver&.close rescue nil
          end
        end

        # Wait for thread with timeout
        result = query_thread.join(dns_timeout)

        if result.nil?
          # Timeout occurred - kill the thread
          query_thread.kill
          error_msg = "DNS query timed out after #{dns_timeout}s"
        else
          # Thread completed
          thread_result = query_thread.value
          if thread_result[:success]
            resolved = true
            resolved_addresses = thread_result[:addresses]
          else
            error_msg = thread_result[:error]
          end
        end

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        latency_ms = [[end_time - start_time, dns_timeout].min * 1000, 0].max.round(2)

        if resolved
          result = {
            reachable: true,
            latency_ms: latency_ms,
            resolved_addresses: resolved_addresses
          }

          record_result(
            reachable: true,
            latency_ms: latency_ms
          )
        else
          result = {
            reachable: false,
            latency_ms: latency_ms,
            error_message: error_msg
          }

          record_result(
            reachable: false,
            latency_ms: latency_ms,
            error_message: error_msg
          )
        end

        result
      end

      private

    end
  end
end
