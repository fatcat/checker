# frozen_string_literal: true

module Checker
  class App
    # Run tests manually for all enabled hosts
    post '/api/tests/run' do
      results = Testers.run_all(build_test_config)
      json results: results
    end

    # Run test for a specific host
    post '/api/tests/run/:id' do
      host = Host[params[:id].to_i]
      halt 404, json(error: 'Host not found') unless host

      tester = Testers.for(host, build_test_config)
      result = tester.run

      json result: result
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
        ping_count: Configuration.get('ping_count').to_i,
        ping_timeout: Configuration.get('ping_timeout_seconds').to_i,
        tcp_timeout: Configuration.get('tcp_timeout_seconds').to_i,
        http_timeout: Configuration.get('http_timeout_seconds').to_i
      }
    end
  end
end
