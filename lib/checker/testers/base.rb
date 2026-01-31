# frozen_string_literal: true

module Checker
  module Testers
    class Base
      attr_reader :test, :config

      def initialize(test, config = {})
        @test = test
        @config = config
        @record_results = config.fetch(:record_results, true)
      end

      def run
        raise NotImplementedError, "Subclasses must implement #run"
      end

      def record_result(reachable:, latency_ms: nil, jitter_ms: nil, http_status: nil, error_message: nil)
        # Skip recording if this is a validation test
        return unless @record_results

        DB[:measurements].insert(
          host_id: test.host_id,
          test_type: test.test_type,
          reachable: reachable,
          latency_ms: latency_ms,
          jitter_ms: jitter_ms,
          http_status: http_status,
          error_message: error_message,
          tested_at: Time.now,
          created_at: Time.now
        )
      end

      protected

      def timeout
        config[:timeout] || 5
      end

      def address
        test.host.address
      end

      def port
        test.port
      end

      def host
        test.host
      end
    end
  end
end
