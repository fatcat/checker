# frozen_string_literal: true

module Checker
  class Configuration
    DEFAULT_SETTINGS = {
      'test_interval_seconds' => 300,        # 5 minutes
      'raw_data_retention_days' => 14,
      'aggregation_15min_retention_days' => 30,
      'http_timeout_seconds' => 10,
      'tcp_timeout_seconds' => 5,
      'dns_timeout_seconds' => 5,
      'ping_count' => 5,                     # Number of pings for jitter calculation
      'ping_timeout_seconds' => 5,
      'log_rotation_period' => 'hourly',     # hourly or daily
      'log_retention_count' => 12,           # Number of log files to keep
      'theme' => 'dark-default',             # Current theme ID
      'outlier_detection_enabled' => true,   # Retest outlier results
      'outlier_threshold_multiplier' => 10,  # Result must be this many times worse than average
      'outlier_min_threshold_ms' => 500      # Minimum difference in ms to be considered an outlier
    }.freeze

    class << self
      def get(key)
        setting = DB[:settings].where(key: key.to_s).first
        setting ? setting[:value] : DEFAULT_SETTINGS[key.to_s]
      end

      def set(key, value)
        DB[:settings].insert_conflict(
          target: :key,
          update: { value: value.to_s, updated_at: Time.now }
        ).insert(key: key.to_s, value: value.to_s)
      end

      def all
        stored = DB[:settings].all.each_with_object({}) do |row, hash|
          hash[row[:key]] = row[:value]
        end
        DEFAULT_SETTINGS.merge(stored)
      end

      def test_interval
        get('test_interval_seconds').to_i
      end

      # Build configuration hash for testers
      # Centralizes timeout configuration used by scheduler and routes
      def test_config
        {
          ping_count: (get('ping_count') || 5).to_i,
          ping_timeout: (get('ping_timeout_seconds') || 5).to_i,
          tcp_timeout: (get('tcp_timeout_seconds') || 5).to_i,
          http_timeout: (get('http_timeout_seconds') || 10).to_i,
          dns_timeout: (get('dns_timeout_seconds') || 5).to_i
        }
      end
    end
  end
end
