# frozen_string_literal: true

require 'logger'
require 'fileutils'

module Checker
  # Rotating logger with configurable rotation period and retention
  class RotatingLogger
    VALID_ROTATION_PERIODS = %w[hourly daily].freeze
    DEFAULT_ROTATION_PERIOD = 'hourly'
    DEFAULT_RETENTION_COUNT = 12

    attr_reader :rotation_period, :retention_count

    def initialize(base_path, rotation_period: nil, retention_count: nil)
      @base_path = base_path
      @rotation_period = validate_rotation_period(rotation_period)
      @retention_count = validate_retention_count(retention_count)
      FileUtils.mkdir_p(File.dirname(@base_path))
      @current_period = nil
      @logger = nil
      @mutex = Mutex.new
      rotate_if_needed
    end

    def reconfigure(rotation_period: nil, retention_count: nil)
      @mutex.synchronize do
        new_period = validate_rotation_period(rotation_period)
        new_count = validate_retention_count(retention_count)

        # Force rotation if period changed
        if new_period != @rotation_period
          @rotation_period = new_period
          @current_period = nil
        end

        @retention_count = new_count
      end
    end

    %i[debug info warn error fatal].each do |level|
      define_method(level) do |message|
        @mutex.synchronize do
          rotate_if_needed
          @logger.send(level, message)
        end
      end
    end

    def close
      @mutex.synchronize do
        @logger&.close
      end
    end

    private

    def validate_rotation_period(period)
      return DEFAULT_ROTATION_PERIOD unless period
      VALID_ROTATION_PERIODS.include?(period) ? period : DEFAULT_ROTATION_PERIOD
    end

    def validate_retention_count(count)
      return DEFAULT_RETENTION_COUNT unless count
      count = count.to_i
      count.positive? ? [count, 168].min : DEFAULT_RETENTION_COUNT # Max 168 (1 week of hourly)
    end

    def current_period_key
      case @rotation_period
      when 'hourly'
        Time.now.strftime('%Y%m%d%H')
      when 'daily'
        Time.now.strftime('%Y%m%d')
      else
        Time.now.strftime('%Y%m%d%H')
      end
    end

    def period_format
      case @rotation_period
      when 'hourly'
        '%Y%m%d%H'
      when 'daily'
        '%Y%m%d'
      else
        '%Y%m%d%H'
      end
    end

    def period_seconds
      case @rotation_period
      when 'hourly'
        3600
      when 'daily'
        86400
      else
        3600
      end
    end

    def rotate_if_needed
      period_key = current_period_key
      return if period_key == @current_period

      @logger&.close
      @current_period = period_key
      log_file = "#{@base_path}.#{period_key}"
      @logger = ::Logger.new(log_file)
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end

      cleanup_old_logs
    end

    def cleanup_old_logs
      cutoff = Time.now - (@retention_count * period_seconds)
      format = period_format
      pattern_length = format.gsub('%', '').length + format.count('%') * 2

      Dir.glob("#{@base_path}.*").each do |file|
        timestamp = file.split('.').last
        next unless timestamp.match?(/^\d{#{pattern_length}}$/)

        begin
          file_time = Time.strptime(timestamp, format)
          File.delete(file) if file_time < cutoff
        rescue ArgumentError
          # Invalid timestamp format, skip
        end
      end
    end
  end

  class << self
    def logger
      @logger ||= create_logger
    end

    def logger=(custom_logger)
      @logger = custom_logger
    end

    def reconfigure_logger
      return unless @logger.respond_to?(:reconfigure)

      # Get settings from Configuration if available
      if defined?(Configuration)
        rotation = Configuration.get('log_rotation_period') || 'hourly'
        retention = Configuration.get('log_retention_count')&.to_i || 12
        @logger.reconfigure(rotation_period: rotation, retention_count: retention)
      end
    end

    private

    def create_logger
      log_dir = ENV.fetch('LOG_DIR') { File.join(Dir.pwd, 'log') }
      log_path = File.join(log_dir, 'checker.log')

      # Try to get settings from Configuration if available
      rotation = 'hourly'
      retention = 12

      if defined?(Configuration)
        rotation = Configuration.get('log_rotation_period') || 'hourly'
        retention = Configuration.get('log_retention_count')&.to_i || 12
      end

      RotatingLogger.new(log_path, rotation_period: rotation, retention_count: retention)
    end
  end
end
