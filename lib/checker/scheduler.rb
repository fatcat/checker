# frozen_string_literal: true

require 'rufus-scheduler'
require_relative 'testers'

module Checker
  class Scheduler
    attr_reader :scheduler, :test_job, :aggregation_job

    # Check for due tests every 10 seconds
    CHECK_INTERVAL = 10

    def initialize
      @scheduler = Rufus::Scheduler.new
      @running = false
    end

    def start
      return if @running

      @running = true
      initialize_test_schedules
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
      # Run all enabled tests for all enabled hosts immediately
      perform_tests_for_all_hosts
    end

    def run_test_for_host(host_id)
      # Run all tests for a specific host
      host = Host[host_id]
      return [] unless host&.enabled

      config = build_test_config
      base_interval = Configuration.test_interval
      results = []

      host.tests_dataset.where(enabled: true).each do |test|
        result = Testers.run_single(test, config)
        results << result

        # Update next_test_at with randomness
        test.update(next_test_at: test.calculate_next_test_time(base_interval))

        log_test_result(host, test, result)
      end

      results
    end

    private

    def initialize_test_schedules
      # Set initial next_test_at for any tests that don't have one
      base_interval = Configuration.test_interval

      Host.all_enabled_tests.each do |test|
        next if test.next_test_at

        # Stagger initial tests to avoid thundering herd
        random_delay = rand(0..base_interval)
        test.update(next_test_at: Time.now + random_delay)
      end

      test_count = Host.all_enabled_tests.count
      Checker.logger.info "Initialized test schedules for #{test_count} tests"
    end

    def schedule_test_checks
      # Check every 10 seconds for tests that are due for execution
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

      # Query: Get all enabled tests where next_test_at <= now
      due_tests = Test.enabled
        .where(host_id: Host.enabled.select(:id))
        .where { next_test_at <= now }
        .all

      # Include tests that have never been run
      due_tests += Test.enabled
        .where(host_id: Host.enabled.select(:id))
        .where(next_test_at: nil)
        .all

      return if due_tests.empty?

      results = []

      due_tests.each do |test|
        host = test.host
        next unless host # Safety check

        result = Testers.run_single(test, config)
        results << { test: test, result: result }

        # Calculate next test time with host's randomness
        test.update(next_test_at: test.calculate_next_test_time(base_interval))

        log_test_result(host, test, result)
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
        host.tests_dataset.where(enabled: true).each do |test|
          result = Testers.run_single(test, config)
          results << { test: test, result: result }

          # Reset next_test_at after manual run
          test.update(next_test_at: test.calculate_next_test_time(base_interval))
        end
      end

      Checker.logger.info "Manual run: executed #{results.size} tests"

      results.each do |r|
        log_test_result(r[:test].host, r[:test], r[:result], indent: true)
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
        ping_count: (Configuration.get('ping_count') || 5).to_i,
        ping_timeout: (Configuration.get('ping_timeout_seconds') || 5).to_i,
        tcp_timeout: (Configuration.get('tcp_timeout_seconds') || 5).to_i,
        http_timeout: (Configuration.get('http_timeout_seconds') || 10).to_i,
        dns_timeout: (Configuration.get('dns_timeout_seconds') || 5).to_i
      }
    end

    def log_test_result(host, test, result, indent: false)
      prefix = indent ? '  ' : ''
      status = result[:reachable] ? 'UP' : 'DOWN'
      latency = result[:latency_ms] ? "#{result[:latency_ms]}ms" : 'N/A'
      test_info = format_test_info(host, test)
      error_info = result[:error] ? " - #{result[:error]}" : ''

      Checker.logger.info "#{prefix}#{host.name} [#{test_info}]: #{status} (#{latency})#{error_info}"
    end

    def format_test_info(host, test)
      case test.test_type
      when 'ping'
        "PING #{host.address}"
      when 'tcp'
        "TCP #{host.address}:#{test.port}"
      when 'http'
        "HTTP #{test.http_scheme}://#{host.address}:#{test.port}"
      when 'dns'
        "DNS #{host.address} -> #{test.dns_query_hostname}"
      else
        "#{test.test_type.upcase} #{host.address}"
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
