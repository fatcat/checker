# frozen_string_literal: true

module Checker
  module Testers
    class Base
      attr_reader :host, :config

      def initialize(host, config = {})
        @host = host
        @config = config
      end

      def run
        raise NotImplementedError, "Subclasses must implement #run"
      end

      def record_result(reachable:, latency_ms: nil, jitter_ms: nil, http_status: nil, error_message: nil)
        DB[:measurements].insert(
          host_id: host[:id] || host.id,
          test_type: host[:test_type] || host.test_type,
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
        host[:address] || host.address
      end

      def port
        host[:port] || host.port
      end
    end
  end
end
