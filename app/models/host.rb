# frozen_string_literal: true

module Checker
  class Host < Sequel::Model(:hosts)
    one_to_many :measurements

    plugin :timestamps, update_on_create: true
    plugin :validation_helpers

    VALID_TEST_TYPES = %w[ping tcp udp http dns].freeze

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
      validates_presence [:name, :address, :test_type]
      validates_includes VALID_TEST_TYPES, :test_type
      validates_presence :port if %w[tcp udp http].include?(test_type)
      validates_presence :dns_query_hostname if test_type == 'dns'

      # Address validation based on test type
      if address && !address.to_s.strip.empty?
        if test_type == 'dns'
          # DNS test requires the address to be a DNS server IP
          errors.add(:address, 'must be a valid IPv4 address for DNS tests') unless valid_ipv4?(address)
        else
          # Other tests accept either IPv4 or hostname
          errors.add(:address, 'must be a valid IPv4 address or hostname') unless valid_address?(address)
        end
      end

      # DNS query hostname must be a valid hostname
      if test_type == 'dns' && dns_query_hostname && !dns_query_hostname.to_s.strip.empty?
        unless valid_hostname?(dns_query_hostname)
          errors.add(:dns_query_hostname, 'must be a valid hostname')
        end
      end
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
