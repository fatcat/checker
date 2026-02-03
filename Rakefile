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

    # Get applied migrations to calculate target version
    applied = Sequel::Migrator.migrator_class(migrations_path).new(db, migrations_path).applied_migrations
    if applied.empty?
      puts "No migrations to rollback"
    else
      # Calculate target: current version minus 1
      current_version = applied.map { |m| m.to_i }.max
      target_version = [current_version - 1, 0].max
      Sequel::Migrator.run(db, migrations_path, target: target_version)
      puts "Rolled back from version #{current_version} to #{target_version}"
    end
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
    require_relative 'config/application'
    Dir['./app/models/*.rb'].each { |f| require f }

    # Sample hosts with their tests
    sample_data = [
      {
        host: { name: 'Google DNS', address: '8.8.8.8', enabled: true, randomness_percent: 5 },
        tests: [{ test_type: 'ping', enabled: true }]
      },
      {
        host: { name: 'Cloudflare DNS', address: '1.1.1.1', enabled: true, randomness_percent: 5 },
        tests: [{ test_type: 'ping', enabled: true }]
      },
      {
        host: { name: 'Google', address: 'google.com', enabled: true, randomness_percent: 5 },
        tests: [
          { test_type: 'ping', enabled: true },
          { test_type: 'http', enabled: true, port: 443, http_scheme: 'https' }
        ]
      },
      {
        host: { name: 'IBM DNS', address: '9.9.9.9', enabled: true, randomness_percent: 5 },
        tests: [
          { test_type: 'ping', enabled: true },
          { test_type: 'dns', enabled: true, dns_query_hostname: 'www.ibm.com' }
        ]
      }
    ]

    DB.transaction do
      sample_data.each do |data|
        # Create host
        host_id = DB[:hosts].insert(
          data[:host].merge(created_at: Time.now, updated_at: Time.now)
        )

        # Create tests for this host
        data[:tests].each do |test|
          DB[:tests].insert(
            test.merge(
              host_id: host_id,
              created_at: Time.now,
              updated_at: Time.now
            )
          )
        end
      end
    end

    puts "Seeded #{sample_data.count} sample hosts with multiple tests"
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

    results = Checker::Testers.run_all(Checker::Configuration.test_config)

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

# Test tasks
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/test_*.rb']
  t.verbose = true
  t.warning = false
end

task default: :test
