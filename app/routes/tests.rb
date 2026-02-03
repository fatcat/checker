# frozen_string_literal: true

module Checker
  class App
    # Run tests manually for all enabled hosts
    post '/api/tests/run' do
      results = Testers.run_all(Configuration.test_config)
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
  end
end
