# frozen_string_literal: true

module Checker
  class App
    # List all hosts
    get '/api/hosts' do
      hosts = DB[:hosts].all
      json hosts: hosts
    end

    # Get host status summary for dashboard
    get '/api/hosts/status' do
      hosts = Host.enabled.map(&:status_summary)
      json hosts: hosts
    end

    # Get a single host
    get '/api/hosts/:id' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host
      json host.values
    end

    # Create a new host
    post '/api/hosts' do
      data = json_body
      host = Host.new(
        name: data[:name],
        address: data[:address],
        port: data[:port],
        test_type: data[:test_type] || 'ping',
        dns_query_hostname: data[:dns_query_hostname],
        randomness_percent: data[:randomness_percent] || 0,
        enabled: data.fetch(:enabled, true)
      )

      if host.valid?
        host.save
        status 201
        json host.values
      else
        status 422
        json error: 'Validation failed', details: host.errors
      end
    end

    # Update a host
    put '/api/hosts/:id' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host

      data = json_body
      host.set(
        name: data[:name] || host.name,
        address: data[:address] || host.address,
        port: data[:port],
        test_type: data[:test_type] || host.test_type,
        dns_query_hostname: data[:dns_query_hostname],
        randomness_percent: data.fetch(:randomness_percent, host.randomness_percent),
        enabled: data.fetch(:enabled, host.enabled)
      )

      if host.valid?
        host.save
        json host.values
      else
        status 422
        json error: 'Validation failed', details: host.errors
      end
    end

    # Delete a host
    delete '/api/hosts/:id' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host

      host.destroy
      status 204
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

    # Get host statistics
    get '/api/hosts/:id/stats' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host

      range = params[:range] || '24h'
      interval = Measurement.time_range_to_interval(range)
      since = Time.now - interval

      measurements = Measurement.for_host(host.id, since: since).all

      total = measurements.count
      successful = measurements.count(&:reachable)
      latencies = measurements.map { |m| m.latency_ms }.compact
      jitters = measurements.map { |m| m.jitter_ms }.compact

      json(
        total_tests: total,
        successful_tests: successful,
        uptime_percent: total > 0 ? ((successful.to_f / total) * 100).round(2) : 0,
        avg_latency: latencies.any? ? (latencies.sum / latencies.size).round(2) : nil,
        min_latency: latencies.min&.round(2),
        max_latency: latencies.max&.round(2),
        avg_jitter: jitters.any? ? (jitters.sum / jitters.size).round(2) : nil,
        last_test: measurements.last&.tested_at&.iso8601
      )
    end
  end
end
