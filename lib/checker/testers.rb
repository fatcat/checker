# frozen_string_literal: true

require_relative 'testers/base'
require_relative 'testers/ping'
require_relative 'testers/tcp'
require_relative 'testers/http'
require_relative 'testers/dns'
require_relative 'testers/jitter'

module Checker
  module Testers
    class << self
      def for(test, config = {})
        test_type = test[:test_type] || test.test_type

        case test_type.to_s.downcase
        when 'ping'
          Ping.new(test, config)
        when 'tcp'
          Tcp.new(test, config)
        when 'http'
          Http.new(test, config)
        when 'dns'
          Dns.new(test, config)
        when 'jitter'
          Jitter.new(test, config)
        else
          raise ArgumentError, "Unknown test type: #{test_type}"
        end
      end

      def run_single(test, config = {})
        tester = self.for(test, config)
        tester.run
      rescue StandardError => e
        { reachable: false, error: e.message }
      end

      def run_all(config = {})
        results = []

        Host.enabled.each do |host|
          host.tests_dataset.where(enabled: true).each do |test|
            result = run_single(test, config)
            results << {
              host_id: host.id,
              host_name: host.name,
              test_type: test.test_type,
              test_id: test.id,
              result: result
            }
          end
        end

        results
      end
    end
  end
end
