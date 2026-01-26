# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default, ENV.fetch('RACK_ENV', 'development').to_sym)

# Load configuration
require_relative 'config/database'
require_relative 'config/application'

# Run migrations automatically (unless explicitly disabled)
unless ENV['SKIP_MIGRATIONS']
  Checker::Database.migrate!
end

# Load models
Dir[File.join(__dir__, 'app', 'models', '*.rb')].each { |file| require file }

# Load the checker library (testers, scheduler, aggregator)
require_relative 'lib/checker'

# Load the application
require_relative 'app/app'

# Start the scheduler in a background thread (unless disabled)
unless ENV['DISABLE_SCHEDULER']
  Thread.new do
    sleep 2  # Wait for app to fully start
    Checker.start_scheduler
  end
end

# Run the app
run Checker::App
