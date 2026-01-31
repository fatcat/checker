# frozen_string_literal: true

module Checker
  class Test < Sequel::Model(:tests)
    many_to_one :host
    one_to_many :measurements, key: :host_id, conditions: -> { { test_type: test_type } }

    plugin :timestamps, update_on_create: true
    plugin :validation_helpers

    VALID_TEST_TYPES = %w[ping tcp http dns].freeze

    def validate
      super
      validates_presence [:host_id, :test_type]
      validates_includes VALID_TEST_TYPES, :test_type

      # Port validation for TCP and HTTP
      if %w[tcp http].include?(test_type)
        validates_presence :port
        validates_integer :port if port
        if port
          validates_operator :>=, 1, :port
          validates_operator :<=, 65535, :port
        end
      end

      # HTTP scheme validation
      if test_type == 'http'
        validates_presence :http_scheme
        validates_includes %w[http https], :http_scheme if http_scheme
      end

      # DNS hostname validation
      if test_type == 'dns'
        validates_presence :dns_query_hostname
        if dns_query_hostname && !dns_query_hostname.to_s.strip.empty?
          unless valid_hostname?(dns_query_hostname)
            errors.add(:dns_query_hostname, 'must be a valid hostname')
          end
        end
      end
    end

    def self.enabled
      where(enabled: true)
    end

    def self.for_host(host_id)
      where(host_id: host_id).order(:test_type)
    end

    def latest_measurement
      Measurement.where(host_id: host_id, test_type: test_type)
        .order(Sequel.desc(:tested_at))
        .first
    end

    # Latency thresholds for degraded status (in milliseconds)
    DEGRADED_THRESHOLDS = {
      'ping' => 1000,  # > 1 second
      'tcp' => 1000,   # > 1 second
      'http' => 2000,  # > 2 seconds
      'dns' => 2000    # > 2 seconds
    }.freeze

    def status
      latest = latest_measurement
      return 'never' if latest.nil?
      return 'failure' unless latest.reachable

      # Check if degraded based on latency threshold
      if degraded?(latest)
        'degraded'
      else
        'success'
      end
    end

    def status_color
      case status
      when 'success' then 'green'
      when 'degraded' then 'yellow'
      when 'failure' then 'red'
      when 'never' then 'gray'
      end
    end

    def degraded?(measurement = nil)
      measurement ||= latest_measurement
      return false unless measurement&.reachable
      return false unless measurement.latency_ms

      threshold = DEGRADED_THRESHOLDS[test_type]
      return false unless threshold

      measurement.latency_ms > threshold
    end

    def calculate_next_test_time(base_interval)
      randomness = host.randomness_percent || 0
      variation_seconds = (base_interval * randomness / 100.0).to_i
      random_offset = rand(-variation_seconds..variation_seconds)
      Time.now + base_interval + random_offset
    end

    def to_api_v2
      latest = latest_measurement
      {
        id: id,
        test_type: test_type,
        port: port,
        http_scheme: http_scheme,
        dns_query_hostname: dns_query_hostname,
        enabled: enabled,
        status: status,
        status_color: status_color,
        latest_result: latest ? {
          reachable: latest.reachable,
          latency_ms: latest.latency_ms,
          jitter_ms: latest.jitter_ms,
          http_status: latest.http_status,
          error_message: latest.error_message,
          tested_at: latest.tested_at.iso8601
        } : nil,
        next_test_at: next_test_at&.iso8601
      }
    end

    private

    def valid_hostname?(value)
      # Use Host model's hostname validation
      return false unless host
      host.valid_hostname?(value)
    end
  end
end
