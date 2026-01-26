# frozen_string_literal: true

module Checker
  class App
    # Get latency data for charts (all hosts combined)
    get '/api/measurements/latency' do
      series = Measurement.latency_series(
        range: params[:range],
        start_time: params[:start],
        end_time: params[:end]
      )
      json series: series
    end

    # Get latency data grouped by test type
    get '/api/measurements/latency/by-type' do
      series_by_type = Measurement.latency_series_by_type(
        range: params[:range],
        start_time: params[:start],
        end_time: params[:end]
      )
      test_types = Measurement.test_types_with_hosts
      json series_by_type: series_by_type, test_types: test_types
    end

    # Get jitter data for charts
    get '/api/measurements/jitter' do
      series = Measurement.jitter_series(
        range: params[:range],
        start_time: params[:start],
        end_time: params[:end]
      )
      json series: series
    end

    # Get reachability data for charts
    get '/api/measurements/reachability' do
      series = Measurement.reachability_series(
        range: params[:range],
        start_time: params[:start],
        end_time: params[:end]
      )
      json series: series
    end

    # Get measurements for a specific host
    get '/api/measurements/host/:id' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host

      range = params[:range] || '24h'
      interval = Measurement.time_range_to_interval(range)
      since = Time.now - interval

      measurements = Measurement.for_host(host.id, since: since).all
      json measurements: measurements.map(&:values)
    end
  end
end
