# frozen_string_literal: true

require 'sequel'
require 'logger'
require 'fileutils'

module Checker
  class Database
    class << self
      attr_reader :connection

      def connect(env = ENV.fetch('RACK_ENV', 'development'))
        db_path = ENV.fetch('DATABASE_PATH') do
          File.expand_path("../../db/checker_#{env}.sqlite3", __FILE__)
        end

        # Ensure database directory exists
        FileUtils.mkdir_p(File.dirname(db_path))

        @connection = Sequel.sqlite(db_path)
        @connection.loggers << Logger.new($stdout) if env == 'development'

        # Enable foreign keys for SQLite
        @connection.run('PRAGMA foreign_keys = ON')

        @connection
      end

      def migrate!
        return unless @connection

        Sequel.extension :migration
        migrations_path = File.expand_path('../../db/migrations', __FILE__)
        Sequel::Migrator.run(@connection, migrations_path)
      end

      def disconnect
        @connection&.disconnect
      end
    end
  end
end

# Connect to the database
DB = Checker::Database.connect
