# frozen_string_literal: true

module Checker
  class App
    # Host management API

    # List all hosts with nested tests
    get '/api/hosts' do
      hosts = Host.all.map(&:to_api_v2)
      json(hosts: hosts)
    end

    # Get host status summary for dashboard
    get '/api/hosts/status' do
      hosts = Host.enabled.map(&:status_summary)
      json hosts: hosts
    end

    # Get single host with tests
    get '/api/hosts/:id' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host
      json host.to_api_v2
    end

    # Create host with tests
    post '/api/hosts' do
      data = json_body

      DB.transaction do
        # Create host
        host = Host.new(
          name: data[:name],
          address: data[:address],
          enabled: data.fetch(:enabled, true),
          randomness_percent: data.fetch(:randomness_percent, 5),
          jitter_enabled: data.fetch(:jitter_enabled, false)
        )

        unless host.valid?
          halt 422, json(error: 'Host validation failed', details: host.errors)
        end
        host.save

        # Create tests
        tests_data = data[:tests] || []

        tests = []
        tests_data.each do |test_data|
          test = Test.new(
            host_id: host.id,
            test_type: test_data[:test_type],
            port: test_data[:port],
            http_scheme: test_data[:http_scheme],
            dns_query_hostname: test_data[:dns_query_hostname],
            enabled: test_data.fetch(:enabled, true)
          )

          unless test.valid?
            halt 422, json(error: 'Test validation failed', details: test.errors)
          end
          test.save
          tests << test
        end

        # Run immediate validation tests if requested
        if data[:validate_immediately]
          config = build_test_config.merge(record_results: false)
          validation_results = tests.map do |test|
            result = Testers.run_single(test, config)
            { test_id: test.id, test_type: test.test_type, result: result }
          end

          status 201
          json host.to_api_v2.merge(validation_results: validation_results)
        else
          status 201
          json host.to_api_v2
        end
      end
    end

    # Update host and tests
    put '/api/hosts/:id' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host

      data = json_body

      DB.transaction do
        # Update host metadata
        host.set(
          name: data[:name] || host.name,
          address: data[:address] || host.address,
          enabled: data.fetch(:enabled, host.enabled),
          randomness_percent: data.fetch(:randomness_percent, host.randomness_percent),
          jitter_enabled: data.fetch(:jitter_enabled, host.jitter_enabled)
        )

        unless host.valid?
          halt 422, json(error: 'Host validation failed', details: host.errors)
        end
        host.save

        # Update tests if provided
        if data[:tests]
          # Get current test types (excluding jitter which is auto-managed)
          current_test_types = host.tests.reject { |t| t.test_type == 'jitter' }.map(&:test_type)
          new_test_types = data[:tests].map { |t| t[:test_type] }

          # Remove tests not in the update (excluding jitter)
          to_remove = current_test_types - new_test_types
          unless to_remove.empty?
            # Delete tests individually to ensure they're actually removed
            to_remove.each do |test_type|
              host.tests_dataset.where(test_type: test_type).delete
            end
          end

          # Update or create tests
          data[:tests].each do |test_data|
            test = host.tests_dataset.where(test_type: test_data[:test_type]).first

            if test
              # Update existing
              test.set(
                port: test_data[:port],
                http_scheme: test_data[:http_scheme],
                dns_query_hostname: test_data[:dns_query_hostname],
                enabled: test_data.fetch(:enabled, test.enabled)
              )
              unless test.valid?
                halt 422, json(error: 'Test validation failed', details: test.errors)
              end
              test.save
            else
              # Create new
              test = Test.new(
                host_id: host.id,
                test_type: test_data[:test_type],
                port: test_data[:port],
                http_scheme: test_data[:http_scheme],
                dns_query_hostname: test_data[:dns_query_hostname],
                enabled: test_data.fetch(:enabled, true)
              )
              unless test.valid?
                halt 422, json(error: 'Test validation failed', details: test.errors)
              end
              test.save
            end
          end
        end

        # Run immediate validation if requested
        if data[:validate_immediately]
          config = build_test_config.merge(record_results: false)
          validation_results = host.tests_dataset.all.map do |test|
            result = Testers.run_single(test, config)
            { test_id: test.id, test_type: test.test_type, result: result }
          end

          json host.to_api_v2.merge(validation_results: validation_results)
        else
          json host.to_api_v2
        end
      end
    end

    # Delete host (cascades to tests and measurements)
    delete '/api/hosts/:id' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host

      host.destroy
      status 204
    end

    # Run specific test immediately
    post '/api/tests/:id/run' do
      test = Test[params[:id].to_i]
      halt 404, json(error: 'Test not found') unless test

      config = build_test_config.merge(record_results: false)
      result = Testers.run_single(test, config)
      json(test_id: test.id, test_type: test.test_type, result: result)
    end

    # Run all tests for a host immediately
    post '/api/hosts/:id/run' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host

      results = Checker.scheduler.run_test_for_host(host.id)
      json(host_id: host.id, results: results)
    end

    # Get host statistics (rolling 50-measurement window per test type)
    get '/api/hosts/:id/stats' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host

      range = params[:range] || '24h'
      window_size = 50

      # Get enabled test types for this host
      test_types = host.tests.select(&:enabled).map(&:test_type)

      all_measurements = []
      all_latencies = []
      all_jitters = []

      # Get last 50 measurements per test type
      test_types.each do |test_type|
        measurements = Measurement
          .where(host_id: host.id, test_type: test_type)
          .order(Sequel.desc(:tested_at))
          .limit(window_size)
          .all

        all_measurements.concat(measurements)

        # Collect latencies from latency-based tests (ping, tcp, http, dns)
        if test_type != 'jitter'
          latencies = measurements.map(&:latency_ms).compact
          all_latencies.concat(latencies)
        end

        # Collect jitter from jitter tests (each result is already avg of 5 pings)
        if test_type == 'jitter'
          jitters = measurements.map(&:jitter_ms).compact
          all_jitters.concat(jitters)
        end
      end

      total = all_measurements.count
      successful = all_measurements.count(&:reachable)

      json(
        total_tests: total,
        successful_tests: successful,
        uptime_percent: total > 0 ? ((successful.to_f / total) * 100).round(2) : 0,
        avg_latency: all_latencies.any? ? (all_latencies.sum / all_latencies.size).round(2) : nil,
        min_latency: all_latencies.min&.round(2),
        max_latency: all_latencies.max&.round(2),
        avg_jitter: all_jitters.any? ? (all_jitters.sum / all_jitters.size).round(2) : nil,
        last_test: all_measurements.max_by(&:tested_at)&.tested_at&.iso8601,
        range: range,
        window_size: window_size
      )
    end

    # Hosts management page
    get '/hosts' do
      erb :hosts
    end

    # Host detail page
    get '/hosts/:id' do
      @host = Host[params[:id].to_i]
      halt 404, 'Host not found' unless @host
      erb :host_detail
    end

    private

    def build_test_config
      {
        ping_count: (Configuration.get('ping_count') || 5).to_i,
        ping_timeout: (Configuration.get('ping_timeout_seconds') || 5).to_i,
        tcp_timeout: (Configuration.get('tcp_timeout_seconds') || 5).to_i,
        http_timeout: (Configuration.get('http_timeout_seconds') || 10).to_i,
        dns_timeout: (Configuration.get('dns_timeout_seconds') || 5).to_i
      }
    end
  end
end
