# frozen_string_literal: true

module Checker
  class Host < Sequel::Model(:hosts)
    one_to_many :measurements
    one_to_many :tests

    plugin :timestamps, update_on_create: true
    plugin :validation_helpers

    # Callbacks to manage jitter test creation/deletion
    def before_update
      super
      manage_jitter_test
    end

    def after_create
      super
      manage_jitter_test if jitter_enabled
    end

    # IPv4 address pattern: 4 octets (0-255) separated by dots
    IPV4_PATTERN = /\A(?:(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\z/

    # Hostname pattern per RFC 1123:
    # - Labels separated by dots
    # - Each label: 1-63 chars, alphanumeric and hyphens
    # - Cannot start or end with hyphen
    # - Total max 253 characters
    HOSTNAME_LABEL_PATTERN = /\A[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\z/

    def valid_ipv4?(value)
      return false if value.nil? || value.empty?

      IPV4_PATTERN.match?(value)
    end

    def valid_hostname?(value)
      return false if value.nil? || value.empty?
      return false if value.length > 253

      labels = value.split('.')
      return false if labels.empty?

      labels.all? do |label|
        label.length >= 1 && label.length <= 63 && HOSTNAME_LABEL_PATTERN.match?(label)
      end
    end

    def looks_like_ipv4?(value)
      # Detect if input appears to be an IPv4 attempt (4 dot-separated numbers)
      value.to_s.match?(/\A\d+\.\d+\.\d+\.\d+\z/)
    end

    def valid_address?(value)
      # If it looks like an IP address, validate as IP (prevents 500.500.500.500 passing as hostname)
      if looks_like_ipv4?(value)
        valid_ipv4?(value)
      else
        valid_ipv4?(value) || valid_hostname?(value)
      end
    end

    def validate
      super
      validates_presence [:name, :address]

      # Address validation (accepts IPv4 or hostname)
      if address && !address.to_s.strip.empty?
        errors.add(:address, 'must be a valid IPv4 address or hostname') unless valid_address?(address)
      end

      # Randomness validation (0-50% to prevent excessive variation)
      if randomness_percent
        validates_integer :randomness_percent
        validates_operator :>=, 0, :randomness_percent
        validates_operator :<=, 50, :randomness_percent
      end

      # Jitter requires address to be valid (can't jitter test without address)
      if jitter_enabled && (!address || address.to_s.strip.empty?)
        errors.add(:jitter_enabled, 'cannot be enabled without a valid address')
      end
    end

    def self.enabled
      where(enabled: true)
    end

    # Get all enabled tests across all enabled hosts (for scheduler)
    def self.all_enabled_tests
      Test.enabled.where(host_id: Host.enabled.select(:id))
    end

    def ping_test
      tests_dataset.where(test_type: 'ping').first
    end

    def has_ping_test?
      !ping_test.nil?
    end

    def overall_status
      # Host is "up" if ANY enabled test is successful
      tests_dataset.where(enabled: true).any? do |test|
        test.status == 'success'
      end
    end

    def latest_measurement
      # Get most recent measurement across all tests
      Measurement.where(host_id: id).order(Sequel.desc(:tested_at)).first
    end

    def to_api_v2
      {
        id: id,
        name: name,
        address: address,
        enabled: enabled,
        randomness_percent: randomness_percent || 5,
        jitter_enabled: jitter_enabled || false,
        tests: tests.map(&:to_api_v2),
        overall_status: overall_status,
        created_at: created_at.iso8601,
        updated_at: updated_at.iso8601
      }
    end

    # V1 API compatibility (deprecated)
    def status_summary
      # Include all tests and their statuses for multi-test dashboard display
      enabled_tests = tests_dataset.where(enabled: true).all

      # Get latest measurements for all enabled tests
      latest_measurements = enabled_tests.map(&:latest_measurement).compact

      # Determine overall badge status based on all enabled tests
      test_statuses = enabled_tests.map(&:status)
      has_success = test_statuses.include?('success')
      has_degraded = test_statuses.include?('degraded')
      has_failure = test_statuses.include?('failure')
      all_never = test_statuses.all? { |s| s == 'never' }
      all_failed = test_statuses.all? { |s| s == 'failure' || s == 'never' }

      # Badge status: UP if any test succeeds, DOWN if all tests failed
      badge_status = (has_success || has_degraded) ? 'up' : 'down'

      # Badge color: green if all success, yellow if mixed, red if all failed
      if all_failed
        badge_color = 'red'
      elsif has_degraded || has_failure
        badge_color = 'yellow'
      else
        badge_color = 'green'
      end

      # Calculate aggregate metrics
      # Latency: average across all successful tests
      successful_latencies = latest_measurements.select(&:reachable).map(&:latency_ms).compact
      avg_latency = successful_latencies.any? ? (successful_latencies.sum / successful_latencies.size).round(2) : nil

      # Jitter: from jitter test (not ping test anymore)
      jitter_test = tests_dataset.where(test_type: 'jitter').first
      jitter_measurement = jitter_test&.latest_measurement
      jitter = jitter_measurement&.jitter_ms

      # Last tested: most recent across all tests
      last_tested_time = latest_measurements.map(&:tested_at).compact.max

      # Next test: earliest next_test_at across all enabled tests
      next_test_times = enabled_tests.map(&:next_test_at).compact
      next_test_time = next_test_times.any? ? next_test_times.min : nil

      {
        id: id,
        name: name,
        address: address,
        enabled: enabled,
        randomness_percent: randomness_percent || 0,
        reachable: badge_status == 'up',
        latency_ms: avg_latency,
        jitter_ms: jitter,
        last_tested: last_tested_time&.iso8601,
        next_test_at: next_test_time&.iso8601,
        badge_status: badge_status,
        badge_color: badge_color,
        test_statuses: enabled_tests.map { |t| { test_type: t.test_type, status: t.status, status_color: t.status_color } }
      }
    end

    private

    def manage_jitter_test
      jitter_test = tests_dataset.where(test_type: 'jitter').first

      if jitter_enabled && !jitter_test
        # Create jitter test
        Test.create(
          host_id: id,
          test_type: 'jitter',
          enabled: true,
          next_test_at: nil  # Will be scheduled immediately
        )
      elsif !jitter_enabled && jitter_test
        # Delete jitter test and its measurements
        jitter_test.destroy
      end
    end
  end
end
