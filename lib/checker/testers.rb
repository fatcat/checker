# frozen_string_literal: true

require_relative 'testers/base'
require_relative 'testers/ping'
require_relative 'testers/tcp'
require_relative 'testers/udp'
require_relative 'testers/http'
require_relative 'testers/dns'

module Checker
  module Testers
    class << self
      def for(host, config = {})
        test_type = host[:test_type] || host.test_type

        case test_type.to_s.downcase
        when 'ping'
          Ping.new(host, config)
        when 'tcp'
          Tcp.new(host, config)
        when 'udp'
          Udp.new(host, config)
        when 'http'
          Http.new(host, config)
        when 'dns'
          Dns.new(host, config)
        else
          raise ArgumentError, "Unknown test type: #{test_type}"
        end
      end

      def run_single(host, config = {})
        tester = self.for(host, config)
        tester.run
      rescue StandardError => e
        { reachable: false, error: e.message }
      end

      def run_all(config = {})
        results = []

        Host.enabled.each do |host|
          result = run_single(host, config)
          results << {
            host_id: host.id,
            host_name: host.name,
            test_type: host.test_type,
            result: result
          }
        end

        results
      end
    end
  end
end
