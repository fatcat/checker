# frozen_string_literal: true

require 'rufus-scheduler'
require_relative 'testers'

module Checker
  class Scheduler
    attr_reader :scheduler, :test_job, :aggregation_job

    # Check for due hosts every 10 seconds
    CHECK_INTERVAL = 10

    def initialize
      @scheduler = Rufus::Scheduler.new
      @running = false
    end

    def start
      return if @running

      @running = true
      initialize_host_schedules
      schedule_test_checks
      schedule_aggregation

      Checker.logger.info "Scheduler started"
      @scheduler
    end

    def stop
      @running = false
      @scheduler.shutdown
      Checker.logger.info "Scheduler stopped"
    end

    def running?
      @running
    end

    def run_tests_now
      # Run all enabled hosts immediately
      perform_tests_for_all_hosts
    end

    def run_test_for_host(host_id)
      host = Host[host_id]
      return nil unless host&.enabled

      config = build_test_config
      result = Testers.run_single(host, config)

      # Update next_test_at with randomness
      base_interval = Configuration.test_interval
      host.update(next_test_at: host.calculate_next_test_time(base_interval))

      result
    end

    private

    def initialize_host_schedules
      # Set initial next_test_at for any hosts that don't have one
      base_interval = Configuration.test_interval

      Host.enabled.each do |host|
        next if host.next_test_at

        # Stagger initial tests to avoid thundering herd
        random_delay = rand(0..base_interval)
        host.update(next_test_at: Time.now + random_delay)
      end

      Checker.logger.info "Initialized test schedules for #{Host.enabled.count} hosts"
    end

    def schedule_test_checks
      # Check every 10 seconds for hosts that are due for testing
      @test_job = @scheduler.every("#{CHECK_INTERVAL}s", first_in: '5s') do
        check_and_run_due_tests
      end

      interval = Configuration.test_interval
      Checker.logger.info "Checking for due tests every #{CHECK_INTERVAL}s (base interval: #{interval}s)"
    end

    def schedule_aggregation
      # Run aggregation daily at 2 AM
      @aggregation_job = @scheduler.cron('0 2 * * *') do
        perform_aggregation
      end

      Checker.logger.info "Aggregation scheduled daily at 2 AM"
    end

    def check_and_run_due_tests
      now = Time.now
      config = build_test_config
      base_interval = Configuration.test_interval

      due_hosts = Host.enabled.where { next_test_at <= now }.all
      due_hosts += Host.enabled.where(next_test_at: nil).all

      return if due_hosts.empty?

      results = []

      due_hosts.each do |host|
        result = Testers.run_single(host, config)
        results << { host: host, result: result }

        # Calculate next test time with randomness
        host.update(next_test_at: host.calculate_next_test_time(base_interval))

        log_test_result(host, result)
      end

      results
    rescue StandardError => e
      Checker.logger.error "Error running tests: #{e.message}"
      Checker.logger.error e.backtrace.first(5).join("\n")
      []
    end

    def perform_tests_for_all_hosts
      config = build_test_config
      base_interval = Configuration.test_interval
      results = []

      Host.enabled.each do |host|
        result = Testers.run_single(host, config)
        results << { host: host, result: result }

        # Reset next_test_at after manual run
        host.update(next_test_at: host.calculate_next_test_time(base_interval))
      end

      Checker.logger.info "Manual run: tested #{results.size} hosts"

      results.each do |r|
        log_test_result(r[:host], r[:result], indent: true)
      end

      results
    rescue StandardError => e
      Checker.logger.error "Error running tests: #{e.message}"
      Checker.logger.error e.backtrace.first(5).join("\n")
      []
    end

    def perform_aggregation
      Aggregator.run
    rescue StandardError => e
      Checker.logger.error "Error running aggregation: #{e.message}"
    end

    def build_test_config
      {
        ping_count: Configuration.get('ping_count').to_i,
        ping_timeout: Configuration.get('ping_timeout_seconds').to_i,
        tcp_timeout: Configuration.get('tcp_timeout_seconds').to_i,
        http_timeout: Configuration.get('http_timeout_seconds').to_i
      }
    end

    def log_test_result(host, result, indent: false)
      prefix = indent ? '  ' : ''
      status = result[:reachable] ? 'UP' : 'DOWN'
      latency = result[:latency_ms] ? "#{result[:latency_ms]}ms" : 'N/A'
      test_info = format_test_info(host)
      error_info = result[:error] ? " - #{result[:error]}" : ''

      Checker.logger.info "#{prefix}#{host.name} [#{test_info}]: #{status} (#{latency})#{error_info}"
    end

    def format_test_info(host)
      case host.test_type
      when 'ping'
        "PING #{host.address}"
      when 'tcp'
        "TCP #{host.address}:#{host.port}"
      when 'udp'
        "UDP #{host.address}:#{host.port}"
      when 'http'
        scheme = host.port == 443 ? 'https' : 'http'
        "HTTP #{scheme}://#{host.address}:#{host.port}"
      when 'dns'
        "DNS #{host.address} -> #{host.dns_query_hostname}"
      else
        "#{host.test_type.upcase} #{host.address}"
      end
    end
  end

  # Global scheduler instance
  class << self
    attr_accessor :scheduler

    def start_scheduler
      @scheduler ||= Scheduler.new
      @scheduler.start
    end

    def stop_scheduler
      @scheduler&.stop
    end
  end
end
