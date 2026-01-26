# frozen_string_literal: true

module Checker
  class Host < Sequel::Model(:hosts)
    one_to_many :measurements

    plugin :timestamps, update_on_create: true
    plugin :validation_helpers

    VALID_TEST_TYPES = %w[ping tcp udp http dns].freeze

    def validate
      super
      validates_presence [:name, :address, :test_type]
      validates_includes VALID_TEST_TYPES, :test_type
      validates_presence :port if %w[tcp udp http].include?(test_type)
      validates_presence :dns_query_hostname if test_type == 'dns'
    end

    def self.enabled
      where(enabled: true)
    end

    def latest_measurement
      Measurement.where(host_id: id).order(Sequel.desc(:tested_at)).first
    end

    def status_summary
      latest = latest_measurement
      {
        id: id,
        name: name,
        address: address,
        port: port,
        test_type: test_type,
        dns_query_hostname: dns_query_hostname,
        enabled: enabled,
        randomness_percent: randomness_percent || 0,
        reachable: latest&.reachable || false,
        latency_ms: latest&.latency_ms,
        jitter_ms: latest&.jitter_ms,
        last_tested: latest&.tested_at&.iso8601,
        next_test_at: next_test_at&.iso8601
      }
    end

    def calculate_next_test_time(base_interval)
      variation_seconds = (base_interval * (randomness_percent || 0) / 100.0).to_i
      random_offset = rand(-variation_seconds..variation_seconds)
      Time.now + base_interval + random_offset
    end
  end
end
