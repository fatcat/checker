# frozen_string_literal: true

# Puma configuration file

# The environment to boot in
environment ENV.fetch('RACK_ENV', 'development')

# The port to bind to
port ENV.fetch('PORT', 4567)

# Number of workers (processes)
# For development, single process is fine
workers ENV.fetch('WEB_CONCURRENCY', 0).to_i

# Number of threads per worker
threads_count = ENV.fetch('PUMA_THREADS', 5).to_i
threads threads_count, threads_count

# Preload the application
preload_app!

# Log requests
if ENV.fetch('RACK_ENV', 'development') == 'development'
  plugin :tmp_restart
end

# Callback for when a worker boots
on_worker_boot do
  # Reconnect to the database if using multiple workers
  require_relative 'database'
end
