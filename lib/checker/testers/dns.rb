# frozen_string_literal: true

require 'resolv'
require 'timeout'

module Checker
  module Testers
    class Dns < Base
      def run
        query_hostname = host[:dns_query_hostname] || host.dns_query_hostname
        dns_server = address
        dns_timeout = config[:dns_timeout] || 5

        unless query_hostname && !query_hostname.empty?
          result = { reachable: false, error_message: 'No query hostname configured' }
          record_result(reachable: false, error_message: result[:error_message])
          return result
        end

        latencies = []
        resolved = false
        resolved_addresses = []
        error_msg = nil

        # Perform multiple queries for jitter calculation
        query_count = config[:dns_query_count] || 3

        query_count.times do
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          begin
            Timeout.timeout(dns_timeout) do
              resolver = Resolv::DNS.new(nameserver: [dns_server])
              addresses = resolver.getaddresses(query_hostname)

              if addresses.any?
                resolved = true
                resolved_addresses = addresses.map(&:to_s)
              else
                error_msg = "No addresses returned for #{query_hostname}"
              end

              resolver.close
            end
          rescue Resolv::ResolvError => e
            error_msg = "DNS resolution failed: #{e.message}"
          rescue Timeout::Error
            error_msg = "DNS query timed out after #{dns_timeout}s"
          rescue StandardError => e
            error_msg = "DNS error: #{e.message}"
          end

          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          latencies << ((end_time - start_time) * 1000).round(2)

          break unless resolved
        end

        if resolved
          avg_latency = (latencies.sum / latencies.size).round(2)
          jitter = calculate_ipdv(latencies)

          result = {
            reachable: true,
            latency_ms: avg_latency,
            jitter_ms: jitter,
            resolved_addresses: resolved_addresses
          }

          record_result(
            reachable: true,
            latency_ms: avg_latency,
            jitter_ms: jitter
          )
        else
          result = {
            reachable: false,
            latency_ms: latencies.first,
            error_message: error_msg
          }

          record_result(
            reachable: false,
            latency_ms: latencies.first,
            error_message: error_msg
          )
        end

        result
      end

      private

      def calculate_ipdv(latencies)
        return 0.0 if latencies.size < 2

        delay_variations = []
        (1...latencies.size).each do |i|
          variation = (latencies[i] - latencies[i - 1]).abs
          delay_variations << variation
        end

        (delay_variations.sum / delay_variations.size).round(2)
      end
    end
  end
end
