# frozen_string_literal: true

module Checker
  class App
    # Run tests manually for all enabled hosts
    post '/api/tests/run' do
      results = Testers.run_all(build_test_config)
      json results: results
    end

    # Run test for a specific host (v1 - deprecated, redirects to v2 endpoint)
    post '/api/tests/run/:id' do
      host_id = params[:id].to_i
      # Redirect to v2 API which handles multi-test architecture
      results = Checker.scheduler.run_test_for_host(host_id)
      json(host_id: host_id, results: results)
    end

    # Get scheduler status
    get '/api/scheduler/status' do
      scheduler = Checker.scheduler
      json(
        running: scheduler&.running? || false,
        test_interval: Configuration.test_interval
      )
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
