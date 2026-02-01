# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
ENV['SKIP_MIGRATIONS'] = 'false'
ENV['DISABLE_SCHEDULER'] = 'true'

require 'bundler/setup'
Bundler.require(:default, :test)
require 'minitest/autorun'
require 'minitest/reporters'
Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

# Load application
require_relative '../config/database'
require_relative '../config/application'

# Connect to test database
DB = Checker::Database.connect('test')

# Run migrations before tests
Checker::Database.migrate!

# Load models
Dir[File.expand_path('../app/models/*.rb', __dir__)].each { |f| require f }

# Load checker library
require_relative '../lib/checker'

# Test helper methods
module TestHelpers
  def setup
    super
    truncate_tables
  end

  def truncate_tables
    DB[:measurements].truncate
    DB[:tests].truncate
    DB[:hosts].truncate
    DB[:settings].delete
  end

  def create_host(attributes = {})
    defaults = {
      name: 'Test Host',
      address: '192.168.1.1',
      enabled: true,
      randomness_percent: 5
    }
    Checker::Host.create(defaults.merge(attributes))
  end

  def create_test(host, attributes = {})
    defaults = {
      host_id: host.id,
      test_type: 'ping',
      enabled: true
    }
    Checker::Test.create(defaults.merge(attributes))
  end

  def create_measurement(host, test, attributes = {})
    defaults = {
      host_id: host.id,
      test_type: test.test_type,
      reachable: true,
      latency_ms: 10.5,
      tested_at: Time.now
    }
    Checker::Measurement.create(defaults.merge(attributes))
  end
end

Minitest::Test.include TestHelpers
