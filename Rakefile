# frozen_string_literal: true

require 'bundler/setup'
require 'sequel'

namespace :db do
  desc 'Run database migrations'
  task :migrate do
    env = ENV.fetch('RACK_ENV', 'development')
    db_path = File.expand_path("db/checker_#{env}.sqlite3", __dir__)

    Sequel.extension :migration
    db = Sequel.sqlite(db_path)
    db.run('PRAGMA foreign_keys = ON')

    migrations_path = File.expand_path('db/migrations', __dir__)
    Sequel::Migrator.run(db, migrations_path)

    puts "Migrations completed for #{env} environment"
  end

  desc 'Rollback the last migration'
  task :rollback do
    env = ENV.fetch('RACK_ENV', 'development')
    db_path = File.expand_path("db/checker_#{env}.sqlite3", __dir__)

    Sequel.extension :migration
    db = Sequel.sqlite(db_path)

    migrations_path = File.expand_path('db/migrations', __dir__)
    Sequel::Migrator.run(db, migrations_path, target: Sequel::Migrator.run(db, migrations_path) - 1)

    puts "Rolled back one migration"
  end

  desc 'Reset the database'
  task :reset do
    env = ENV.fetch('RACK_ENV', 'development')
    db_path = File.expand_path("db/checker_#{env}.sqlite3", __dir__)

    File.delete(db_path) if File.exist?(db_path)
    puts "Deleted database: #{db_path}"

    Rake::Task['db:migrate'].invoke
  end

  desc 'Seed the database with sample data'
  task :seed do
    require_relative 'config/database'

    # Add some sample hosts
    hosts = [
      { name: 'Google DNS', address: '8.8.8.8', test_type: 'ping' },
      { name: 'Cloudflare DNS', address: '1.1.1.1', test_type: 'ping' },
      { name: 'Google', address: 'google.com', port: 443, test_type: 'http' }
    ]

    hosts.each do |host|
      DB[:hosts].insert_ignore.insert(host.merge(created_at: Time.now, updated_at: Time.now))
    end

    puts "Seeded #{hosts.count} sample hosts"
  end
end

desc 'Start the development server'
task :server do
  exec 'bundle exec puma -C config/puma.rb'
end

desc 'Start an interactive console'
task :console do
  require_relative 'config/database'
  require_relative 'config/application'
  Dir['./app/models/*.rb'].each { |f| require f }
  require_relative 'lib/checker'

  require 'irb'
  IRB.start
end

namespace :tests do
  desc 'Run tests for all enabled hosts'
  task :run do
    require_relative 'config/database'
    require_relative 'config/application'
    Dir['./app/models/*.rb'].each { |f| require f }
    require_relative 'lib/checker'

    config = {
      ping_count: Checker::Configuration.get('ping_count').to_i,
      ping_timeout: Checker::Configuration.get('ping_timeout_seconds').to_i,
      tcp_timeout: Checker::Configuration.get('tcp_timeout_seconds').to_i,
      http_timeout: Checker::Configuration.get('http_timeout_seconds').to_i
    }

    results = Checker::Testers.run_all(config)

    results.each do |r|
      status = r[:result][:reachable] ? 'UP' : 'DOWN'
      latency = r[:result][:latency_ms] ? "#{r[:result][:latency_ms]}ms" : 'N/A'
      jitter = r[:result][:jitter_ms] ? "#{r[:result][:jitter_ms]}ms" : 'N/A'
      puts "#{r[:host_name]} (#{r[:test_type]}): #{status} - Latency: #{latency}, Jitter: #{jitter}"
    end
  end
end

namespace :aggregation do
  desc 'Run data aggregation manually'
  task :run do
    require_relative 'config/database'
    require_relative 'config/application'
    Dir['./app/models/*.rb'].each { |f| require f }
    require_relative 'lib/checker'

    Checker::Aggregator.run
  end
end

task default: :server
